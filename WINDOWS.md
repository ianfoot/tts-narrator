# tts-narrator — Windows Setup

Getting the app running on Windows from a clean machine: the C++ toolchain
Flutter needs, FVM, and the pinned Flutter SDK this repo expects.

## Prerequisites

- **Git for Windows** on your `Path` — Flutter shells out to Git, and FVM
  cannot fetch an SDK without it. If you already cloned this repo you have it;
  otherwise install it from <https://git-scm.com/download/win> and restart your
  terminal.

## 1. Install Visual Studio Build Tools 2022

Flutter's Windows runner is a native C++/CMake app, so a C++ toolchain has to
exist before the first build.

1. Go to <https://visualstudio.microsoft.com/downloads/>.
2. Scroll to **Tools for Visual Studio**, expand it, and click **Download**
   next to **Build Tools for Visual Studio 2022**.
3. Run `vs_BuildTools.exe`.

In the installer's workload list:

1. Tick **Desktop development with C++**.
2. Look at the **Installation details** panel on the right and expand
   **Desktop development with C++**. Confirm these three are ticked — the
   workload defaults can be deselected somewhere along the way and the failure
   without them is cryptic:
   - **MSVC v143 build tools (x86 & x64)** — the compiler.
   - **Windows 10/11 SDK** — the headers and libs.
   - **C++ CMake tools for Windows** — Flutter generates a CMake project and
     drives it; without this the build fails before compiling anything.
3. Also tick **C++ ATL for v143 build tools (x86 & x64)**. ATL is not strictly
   required by this app's plugin set — the plugins here use plain Win32 and COM —
   but `flutter_secure_storage`'s Windows implementation documents it as a
   prerequisite in its own README, and installing it costs nothing.
4. Click **Install** and wait for it to finish.

## 2. Install FVM manually

FVM pins this repo's Flutter version; see `DEVELOPER.md` for why that matters.

1. Go to <https://github.com/leoafarias/fvm/releases/latest> and under
   **Assets** download **`fvm-<version>-windows-x64.zip`** (currently
   `fvm-4.3.1-windows-x64.zip`; there is also an `-arm64` build for Windows on
   ARM).
2. Open your `Downloads` folder, right-click the `.zip`, choose
   **Extract All...**, set the destination to `C:\fvm`, and extract. You should
   end up with `C:\fvm\fvm.exe`.
3. Put that folder on your **user** `Path`:
   1. Press `Win + R`, type `sysdm.cpl`, press **Enter**.
   2. **Advanced** tab → **Environment Variables** at the bottom.
   3. In the top section (**User variables**) select **Path** → **Edit...**.
   4. **New** → type `C:\fvm`.
   5. **OK** on all three windows.

Only add FVM itself. Flutter's own `bin` deliberately stays off `Path`: this
repo pins an exact SDK version in `.fvmrc`, and a bare `flutter` on `Path` can
resolve a different one. `fvm flutter …` always uses the pinned SDK.

## 3. Install the pinned Flutter SDK

Open a **fresh** PowerShell window (the `Path` change needs a new session) and,
from the **repo root**:

```powershell
fvm --version
fvm install
```

`fvm install` takes no argument on purpose: it reads the version configured for
the project — `3.47.5`, per `.fvmrc` — and installs exactly that. Naming a
version (or setting a global default) would defeat the pin.

Verify:

```powershell
fvm list
```

## 4. Run the app

From the `app` directory:

```powershell
cd app
fvm flutter pub get
fvm flutter run -d windows
```

Other useful invocations, same prefix:

```powershell
fvm flutter test              # widget tests
fvm flutter build windows --release
```

A release build lands in
`app\build\windows\x64\runner\Release\tts_narrator.exe` alongside the DLLs it
needs — copy the whole directory, not just the `.exe`.

## Troubleshooting

**`flutter doctor` complaints.** Run the pinned SDK's own check:

```powershell
fvm flutter doctor -v
```

**Build fails during CMake configuration.** Almost always the *C++ CMake tools
for Windows* component from step 1 being unticked. Use **Visual Studio
Installer** → **Modify** on your Build Tools install and add it.

**`The system cannot find the file specified` on a fresh terminal.** The `Path`
edit has not reached that session — open a new one.

**FVM cannot download the SDK.** Check `git --version` in the same terminal.