# Draft: iOS Metal Shader Resource Fix

## Requirements (confirmed)

- **Core Problem**: `ggml-metal.metal` shader file not bundled in iOS app, causing Metal GPU initialization failure
- **Error**: `GGML_ASSERT(device) failed` after failing to find `ggml-metal.metal`
- **File Location**: `ios/Classes/whisper/ggml/src/ggml-metal/ggml-metal.metal` (416KB)
- **Current Podspec**: Missing `s.resources` declaration for Metal shader

## Technical Decisions

- **Solution Pattern Found**: `mybigday/whisper.rn` and `mybigday/llama.rn` both use:
  ```ruby
  s.resources = "cpp/ggml-metal/ggml-metal.metal"
  ```
- **Bundle Resolution**: Code uses `[NSBundle bundleForClass:[GGMLMetalClass class]]` to find resources
- **Fallback Chain**:
  1. Try `default.metallib` (pre-compiled)
  2. Try `ggml-metal.metal` via bundle path
  3. Fall back to CWD (fails on iOS)

## Research Findings

### From GitHub Analysis:
1. **whisper.rn** (mybigday) uses `s.resources = "cpp/ggml-metal/ggml-metal.metal"` - CONFIRMED WORKING
2. **llama.rn** (mybigday) uses same pattern - CONFIRMED WORKING
3. No Flutter iOS plugins found using Metal resources yet

### From CocoaPods Docs:
- `s.resources = ['path/to/file']` - copies files directly to target bundle
- `s.resource_bundles = {'BundleName' => ['files']}` - recommended for static libs, creates namespaced bundle

### Key Technical Details:
- iOS uses `[NSBundle bundleForClass:[GGMLMetalClass class]]` which resolves to the pod's bundle
- The `pathForResource:ofType:` call looks for files in the bundle's Resources directory
- For Flutter iOS plugins, CocoaPods integrates resources into the framework bundle

## Open Questions

1. **Pre-compiled metallib vs source .metal file?**
   - Source: Compiled at runtime, more flexible, larger file (416KB)
   - Metallib: Pre-compiled, faster startup, requires build toolchain changes
   - *Recommendation*: Use source .metal file (simpler, matches whisper.rn pattern)

2. **macOS parity - does macOS work currently?**
   - Need to verify if macOS has same issue or different behavior
   - macOS podspec doesn't have `s.resources` either

3. **Simulator support?**
   - Metal is supported on iOS Simulator (M1+ required)
   - Same bundle resolution should work

## Scope Boundaries

- **INCLUDE**: iOS podspec fix to bundle Metal shader
- **INCLUDE**: Verification steps for both device and simulator
- **POSSIBLY INCLUDE**: macOS podspec fix if same issue exists
- **EXCLUDE**: Changing Metal initialization C code
- **EXCLUDE**: Pre-compiling to metallib (adds complexity)

## Solution Approach

### Option A: Simple s.resources (RECOMMENDED)
```ruby
s.resources = 'Classes/whisper/ggml/src/ggml-metal/ggml-metal.metal'
```
- Pros: Simple, matches whisper.rn pattern, battle-tested
- Cons: None known

### Option B: resource_bundles (more complex)
```ruby
s.resource_bundles = {
  'whisper_ggml_plus_Metal' => ['Classes/whisper/ggml/src/ggml-metal/ggml-metal.metal']
}
```
- Pros: Namespaced, recommended for static libs
- Cons: More complex, may require code changes for bundle resolution

### Option C: Pre-compile metallib
- Pros: Faster app startup
- Cons: Requires build script, complex for CocoaPods, harder to maintain

## Awaiting User Input

1. Confirm Option A (simple s.resources) is acceptable?
2. Should we also fix macOS podspec for consistency?
3. Any other Metal-related files that should be bundled?
