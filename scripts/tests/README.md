# Switch lifecycle regression harness

Run against the pinned MeloNX source after applying `scripts/patch_switch.py`,
using an already installed .NET 8 SDK:

```sh
python3 scripts/tests/run_switch_lifecycle.py Vendor/MeloNX --dotnet /path/to/dotnet
```

The runner extracts the actual `SignalGpuDone`, `Render`, `Exit`, `MainLoop`,
and `Execute` methods and their lifecycle fields from `WindowBase.cs`. It compiles
them in a fresh temporary project with stub graphics and SDL dependencies. It
does not copy or reimplement those method bodies.

The cases cover stop before startup, stop during window initialization, stop
while the GPU waits on pause, completion timing when the renderer outlives its
callback, repeated stop calls, and 300 concurrent start/stop races. Individual
asynchronous waits have two-second bounds. The test process has a 30-second
bound, configurable with `--timeout`; compilation has a 120-second bound.

No SDKs, NuGet packages, or other files are downloaded. NuGet sources are cleared,
build caches and generated code stay in a temporary directory, and the supplied
source checkout is read-only. The runner requires macOS or Linux for bounded
process-group cleanup.

These tests verify native cancellation and lifecycle control flow. They do not
exercise actual graphics, the iOS ABI, guest CPU execution, or game compatibility.
