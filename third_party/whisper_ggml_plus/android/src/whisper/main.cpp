#include <android/log.h>
#include "main.h"
#include "src/whisper.h"

#define DR_WAV_IMPLEMENTATION
#include "src/examples/dr_wav.h"

#include <cmath>
#include <algorithm>
#include <atomic>
#include <fstream>
#include <cstdio>
#include <string>
#include <sstream>
#include <thread>
#include <vector>
#include <mutex>
#include <iostream>
#include <chrono>
#include "json/json.hpp"
#include <stdio.h>

using json = nlohmann::json;

enum class whisper_vad_mode {
    auto_mode,
    disabled,
    enabled,
};

struct whisper_params
{
    int32_t seed = -1;
    int32_t n_threads = std::min(4, (int32_t)std::thread::hardware_concurrency());

    int32_t n_processors = 1;
    int32_t offset_t_ms = 0;
    int32_t offset_n = 0;
    int32_t duration_ms = 0;
    int32_t max_context = -1;
    int32_t max_len = 0;
    int32_t best_of = 5;
    int32_t beam_size = -1;

    float word_thold = 0.01f;
    float entropy_thold = 2.40f;
    float logprob_thold = -1.00f;

    bool verbose = false;
    bool print_special_tokens = false;
    bool speed_up = false;
    int audio_ctx = 0; // 0 = full 30 s window; else mel frames (50 per second)
    std::string allowed_langs; // comma list, e.g. "en,pl": restrict auto-detect to these
    bool single_pass = false;  // true: one decode with (restricted) auto-detect; false: decode per language
    bool translate = false;
    bool diarize = false;
    bool no_fallback = false;
    bool output_txt = false;
    bool output_vtt = false;
    bool output_srt = false;
    bool output_wts = false;
    bool output_csv = false;
    bool print_special = false;
    bool print_colors = false;
    bool print_progress = false;
    bool no_timestamps = false;
    bool split_on_word = false;
    whisper_vad_mode vad_mode = whisper_vad_mode::auto_mode;

    std::string language = "id";
    std::string prompt;
    std::string model = "";
    std::string audio = "";
    std::string vad_model_path = "";
    std::vector<std::string> fname_inp = {};
    std::vector<std::string> fname_outp = {};
};

static whisper_vad_mode parse_vad_mode(const json & json_body) {
    const std::string vad_mode = json_body.value("vad_mode", std::string("auto"));
    if (vad_mode == "disabled") {
        return whisper_vad_mode::disabled;
    }
    if (vad_mode == "enabled") {
        return whisper_vad_mode::enabled;
    }
    return whisper_vad_mode::auto_mode;
}

static struct whisper_context * g_ctx = nullptr;
static std::string g_model_path = "";
static std::mutex g_mutex;
static std::atomic<bool> g_should_abort(false);

static void dispose_context_locked() {
    if (g_ctx != nullptr) {
        whisper_free(g_ctx);
        g_ctx = nullptr;
    }
    g_model_path.clear();
}

static bool abort_callback(void* user_data) {
    return g_should_abort.load();
}

char *jsonToChar(json jsonData)
{
    try {
        // Ensure ASCII encoding to avoid UTF-8 issues across FFI boundary
        // Non-ASCII characters (Korean, etc.) will be escaped as \uXXXX
        // Use 'replace' instead of 'strict' to handle malformed UTF-8 from Whisper output
        // (e.g., truncated multibyte sequences like 0xEC without following bytes)
        std::string result = jsonData.dump(-1, ' ', true, nlohmann::json::error_handler_t::replace);
        char *ch = new char[result.size() + 1];
        if (ch) {
            strcpy(ch, result.c_str());
        }
        return ch;
    } catch (const std::exception& e) {
        // Fallback for absolute safety
        std::string errorJson = "{\"@type\":\"error\",\"message\":\"JSON serialization failed\"}";
        char *ch = new char[errorJson.size() + 1];
        strcpy(ch, errorJson.c_str());
        return ch;
    }
}

json transcribe(json jsonBody)
{
    std::lock_guard<std::mutex> lock(g_mutex);
    
    g_should_abort.store(false);

    whisper_params params;
    params.n_threads = jsonBody["threads"];
    params.verbose = jsonBody["is_verbose"];
    params.translate = jsonBody["is_translate"];
    params.language = jsonBody["language"];
    params.print_special_tokens = jsonBody["is_special_tokens"];
    params.no_timestamps = jsonBody["is_no_timestamps"];
    params.model = jsonBody["model"];
    params.audio = jsonBody["audio"];
    params.split_on_word = jsonBody["split_on_word"];
    params.diarize = jsonBody["diarize"];
    params.speed_up = jsonBody["speed_up"];
    params.no_fallback = jsonBody.value("no_fallback", false);
    params.audio_ctx = jsonBody.value("audio_ctx", 0);
    params.allowed_langs = jsonBody.value("allowed_langs", std::string(""));
    params.single_pass = jsonBody.value("single_pass", false);
    params.vad_mode = parse_vad_mode(jsonBody);
    params.vad_model_path = jsonBody.value("vad_model_path", std::string(""));

    json jsonResult;
    jsonResult["@type"] = "transcribe";

    if (g_ctx == nullptr || g_model_path != params.model) {
        dispose_context_locked();
        
        whisper_context_params cparams = whisper_context_default_params();
        cparams.use_gpu = false;
        cparams.flash_attn = false;

        g_ctx = whisper_init_from_file_with_params(params.model.c_str(), cparams);
        if (g_ctx != nullptr) {
            g_model_path = params.model;
        }
    }

    if (g_ctx == nullptr)
    {
        jsonResult["@type"] = "error";
        jsonResult["message"] = "failed to initialize whisper context (possibly OOM)";
        return jsonResult;
    }

    std::vector<float> pcmf32;
    {
        drwav wav;
        if (!drwav_init_file(&wav, params.audio.c_str(), NULL))
        {
            jsonResult["@type"] = "error";
            jsonResult["message"] = " failed to open WAV file ";
            return jsonResult;
        }

        int n = wav.totalPCMFrameCount;
        std::vector<int16_t> pcm16(n * wav.channels);
        drwav_read_pcm_frames_s16(&wav, n, pcm16.data());
        drwav_uninit(&wav);

        pcmf32.resize(n);
        if (wav.channels == 1) {
            for (int i = 0; i < n; i++) pcmf32[i] = float(pcm16[i]) / 32768.0f;
        } else {
            for (int i = 0; i < n; i++) pcmf32[i] = float(pcm16[2 * i] + pcm16[2 * i + 1]) / 65536.0f;
        }
    }

    const int model_n_text_layer = whisper_model_n_text_layer(g_ctx);
    const int model_n_vocab = whisper_model_n_vocab(g_ctx);
    const bool is_turbo = (model_n_text_layer == 4 && model_n_vocab == 51866);
    
    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", 
                        "[DEBUG] Model info - n_text_layer: %d, n_vocab: %d, is_turbo: %d", 
                        model_n_text_layer, model_n_vocab, is_turbo);

    whisper_sampling_strategy strategy = WHISPER_SAMPLING_GREEDY; // one pass; beam search is too slow on a phone
    whisper_full_params wparams = whisper_full_default_params(strategy);
    
    wparams.print_realtime = false;
    wparams.print_progress = false;
    wparams.print_timestamps = !params.no_timestamps;
    wparams.translate = params.translate;
    wparams.language = params.language.c_str();
    wparams.n_threads = params.n_threads;
    wparams.split_on_word = params.split_on_word;
    wparams.audio_ctx = params.audio_ctx > 0 ? params.audio_ctx : (params.speed_up ? 768 : 0);
    wparams.single_segment = false;

    if (params.split_on_word) {
        __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                            "[DEBUG] Disabling VAD because split_on_word requires stable timestamps");
        wparams.vad = false;
    } else if (params.vad_mode == whisper_vad_mode::disabled) {
        wparams.vad = false;
    } else if (!params.vad_model_path.empty()) {
        wparams.vad = true;
        wparams.vad_model_path = params.vad_model_path.c_str();
    } else if (params.vad_mode == whisper_vad_mode::enabled) {
        jsonResult["@type"] = "error";
        jsonResult["message"] =
            "VAD was explicitly enabled but no vad_model_path was provided for this platform";
        return jsonResult;
    } else {
        wparams.vad = false;
    }

    wparams.greedy.best_of = 1;

    if (params.split_on_word) {
        wparams.max_len = 1;
        wparams.token_timestamps = true;
    }
    
    wparams.abort_callback = abort_callback;
    wparams.abort_callback_user_data = nullptr;

    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter",
                        "[DEBUG] Transcription params - threads: %d, speed_up: %d, no_timestamps: %d, single_segment: %d, split_on_word: %d, max_len: %d",
                        wparams.n_threads, params.speed_up, wparams.no_timestamps, wparams.single_segment, wparams.split_on_word, wparams.max_len);

    auto start_time = std::chrono::high_resolution_clock::now();

    if (params.no_fallback) {
        wparams.temperature_inc = 0.0f; // one pass, no retries
    }
    wparams.max_tokens = 96; // a sentence, not a runaway loop

    // Languages in play (e.g. "en,pl"). With more than one, the sentence is
    // decoded in EVERY language and the most confident decode wins — no
    // guessing which language was spoken (Whisper's guesser leans English).
    std::vector<std::string> langs;
    if (params.language == "auto" && !params.allowed_langs.empty()) {
        std::stringstream ss(params.allowed_langs);
        std::string tok;
        while (std::getline(ss, tok, ',')) {
            if (!tok.empty() && whisper_lang_id(tok.c_str()) >= 0) langs.push_back(tok);
        }
    }

    // Language-ID probabilities: only used when a single language is in play
    // (with several, the per-language decodes decide — and skipping the ID
    // pass saves an encoder run).
    std::vector<float> lid(whisper_lang_max_id() + 1, 0.0f);
    bool have_lid = false;
    if (langs.size() == 1) {
        if (whisper_pcm_to_mel(g_ctx, pcmf32.data(), pcmf32.size(), wparams.n_threads) == 0 &&
            whisper_lang_auto_detect_ctx(g_ctx, 0, wparams.n_threads, wparams.audio_ctx, lid.data()) >= 0) {
            have_lid = true;
        }
    }

    auto collect = [&](std::string & text, double & logprob, int & ntok) {
        text.clear(); logprob = 0.0; ntok = 0;
        const int n_segments = whisper_full_n_segments(g_ctx);
        const whisper_token eot = whisper_token_eot(g_ctx);
        for (int i = 0; i < n_segments; ++i) {
            text += std::string(whisper_full_get_segment_text(g_ctx, i));
            const int nt = whisper_full_n_tokens(g_ctx, i);
            for (int t = 0; t < nt; ++t) {
                if (whisper_full_get_token_id(g_ctx, i, t) >= eot) continue;
                const float p = whisper_full_get_token_p(g_ctx, i, t);
                logprob += std::log(std::max(p, 1e-6f));
                ntok++;
            }
        }
        if (ntok > 0) logprob /= ntok;
    };

    auto run = [&]() -> bool {
        if (whisper_full(g_ctx, wparams, pcmf32.data(), pcmf32.size()) != 0) {
            if (g_should_abort.load()) {
                jsonResult["@type"] = "aborted";
                jsonResult["message"] = "transcription aborted by user";
                g_should_abort.store(false);
            } else {
                jsonResult["@type"] = "error";
                jsonResult["message"] = "failed to process audio";
            }
            return false;
        }
        return true;
    };

    if (langs.size() >= 2 && params.single_pass) {
        // Strong model: let it hear once and pick among the languages in play.
        whisper_set_allowed_langs(params.allowed_langs.c_str());
        wparams.language = "auto";
        wparams.detect_language = false;
        const bool ok = run();
        whisper_set_allowed_langs("");
        if (!ok) return jsonResult;
        std::string text_result; double lp = 0.0; int ntok = 0;
        collect(text_result, lp, ntok);
        std::string first_lang = whisper_lang_str(whisper_full_lang_id(g_ctx));
        const float lpb = whisper_full_lang_prob(g_ctx);

        // Second look: if the first decode was shaky (low token confidence or a
        // weak language call), decode once more in every OTHER language in play
        // and keep the most confident. Costs an extra encoder run only when unsure.
        const bool shaky = (ntok > 0 && lp < std::log(0.45)) || (lpb >= 0 && lpb < 0.6f);
        std::vector<json> cj;
        {
            json j; j["lang"] = first_lang; j["text"] = text_result; j["logprob"] = lp; j["tokens"] = ntok;
            if (lpb >= 0) j["lid"] = lpb;
            j["score"] = lp; cj.push_back(j);
        }
        std::string best_lang = first_lang, best_text = text_result; double best_lp = lp; bool looked_again = false;
        if (shaky) {
            for (size_t i = 0; i < langs.size(); ++i) {
                if (langs[i] == first_lang) continue;
                wparams.language = langs[i].c_str();
                wparams.detect_language = false;
                if (!run()) return jsonResult;
                looked_again = true;
                std::string t2; double lp2 = 0.0; int n2 = 0;
                collect(t2, lp2, n2);
                json j; j["lang"] = langs[i]; j["text"] = t2; j["logprob"] = lp2; j["tokens"] = n2; j["score"] = lp2;
                cj.push_back(j);
                std::string trimmed = t2; trimmed.erase(0, trimmed.find_first_not_of(" \t\n\r"));
                if (!trimmed.empty() && n2 > 0 && lp2 > best_lp) { best_lp = lp2; best_lang = langs[i]; best_text = t2; }
            }
        }
        auto end_time = std::chrono::high_resolution_clock::now();
        __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", "[DEBUG] Single-pass decode%s in %lldms",
                            looked_again ? " (+second look)" : "",
                            (long long)std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count());
        jsonResult["text"] = best_text;
        jsonResult["logprob"] = best_lp;
        jsonResult["language"] = best_lang;
        if (lpb >= 0) jsonResult["language_prob"] = lpb;
        if (looked_again) { jsonResult["candidates"] = cj; jsonResult["second_look"] = true; }
        return jsonResult;
    }

    if (langs.size() >= 2) {
        struct Cand { std::string lang; std::string text; double logprob; int ntok; float lidp; double score; };
        std::vector<Cand> cands;
        for (size_t i = 0; i < langs.size(); ++i) {
            wparams.language = langs[i].c_str();
            wparams.detect_language = false;
            if (!run()) return jsonResult;
            Cand c; c.lang = langs[i];
            collect(c.text, c.logprob, c.ntok);
            c.lidp = have_lid ? lid[whisper_lang_id(langs[i].c_str())] : -1.0f;
            std::string trimmed = c.text;
            trimmed.erase(0, trimmed.find_first_not_of(" \t\n\r"));
            c.score = trimmed.empty() ? -1e9 : c.logprob + (have_lid ? 0.35 * std::log(std::max(c.lidp, 0.001f)) : 0.0);
            cands.push_back(c);
        }
        size_t best = 0;
        for (size_t i = 1; i < cands.size(); ++i) if (cands[i].score > cands[best].score) best = i;
        double runner = -1e9;
        for (size_t i = 0; i < cands.size(); ++i) if (i != best && cands[i].score > runner) runner = cands[i].score;

        auto end_time = std::chrono::high_resolution_clock::now();
        __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", "[DEBUG] Multi-decode (%zu langs) in %lldms",
                            langs.size(), (long long)std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count());

        std::vector<json> cj;
        for (auto & c : cands) {
            json j; j["lang"] = c.lang; j["text"] = c.text; j["logprob"] = c.logprob; j["tokens"] = c.ntok;
            if (have_lid) j["lid"] = c.lidp;
            j["score"] = c.score;
            cj.push_back(j);
        }
        jsonResult["candidates"] = cj;
        jsonResult["text"] = cands[best].text;
        jsonResult["language"] = cands[best].lang;
        jsonResult["logprob"] = cands[best].logprob;
        jsonResult["margin"] = cands[best].score - runner;
        if (have_lid) jsonResult["language_prob"] = cands[best].lidp;
        return jsonResult;
    }

    // Single language (or plain auto): one decode.
    std::string chosen_lang;
    if (langs.size() == 1) {
        chosen_lang = langs[0];
        wparams.language = chosen_lang.c_str();
        wparams.detect_language = false;
        if (have_lid) jsonResult["language_prob"] = lid[whisper_lang_id(chosen_lang.c_str())];
    }
    if (!run()) return jsonResult;

    auto end_time = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - start_time).count();
    __android_log_print(ANDROID_LOG_DEBUG, "WhisperFlutter", "[DEBUG] Transcription completed in %lldms", (long long)duration);

    std::string text_result; double lp = 0.0; int ntok = 0;
    collect(text_result, lp, ntok);
    if (!params.no_timestamps) {
        std::vector<json> segmentsJson;
        const int n_segments = whisper_full_n_segments(g_ctx);
        for (int i = 0; i < n_segments; ++i) {
            json jsonSegment;
            jsonSegment["from_ts"] = whisper_full_get_segment_t0(g_ctx, i);
            jsonSegment["to_ts"] = whisper_full_get_segment_t1(g_ctx, i);
            jsonSegment["text"] = whisper_full_get_segment_text(g_ctx, i);
            segmentsJson.push_back(jsonSegment);
        }
        jsonResult["segments"] = segmentsJson;
    }
    jsonResult["text"] = text_result;
    jsonResult["logprob"] = lp;
    jsonResult["language"] = whisper_lang_str(whisper_full_lang_id(g_ctx));
    return jsonResult;
}

extern "C"
{
    FUNCTION_ATTRIBUTE char *request(char *body)
    {
        try {
            json jsonBody = json::parse(body);
            if (jsonBody["@type"] == "abort") {
                g_should_abort.store(true);
                return jsonToChar({{"@type", "abort"}, {"message", "abort signal sent"}});
            }
            if (jsonBody["@type"] == "dispose") {
                std::lock_guard<std::mutex> lock(g_mutex);
                dispose_context_locked();
                return jsonToChar({{"@type", "dispose"}, {"message", "whisper context disposed"}});
            }
            if (jsonBody["@type"] == "getTextFromWavFile") {
                return jsonToChar(transcribe(jsonBody));
            }
            if (jsonBody["@type"] == "getVersion") {
                return jsonToChar({{"@type", "version"}, {"message", "lib v1.8.3-accel"}});
            }
            return jsonToChar({{"@type", "error"}, {"message", "method not found"}});
        } catch (const std::exception &e) {
            return jsonToChar({{"@type", "error"}, {"message", e.what()}});
        }
    }

    FUNCTION_ATTRIBUTE void free_string(char *ptr)
    {
        delete[] ptr;
    }
}
