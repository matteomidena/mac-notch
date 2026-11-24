# Spike: process tap under ad-hoc signing

Date: 2026-11-20 · Plan Task 3 · macOS 26.7.1, SDK 26.5

## Verdict

- **GO.** An ad-hoc signed `LSUIElement` app tapped Spotify and read real audio levels every second, using about 0.2% CPU.
- Task 22 can build the live spectrum on the same calls. The decorative-bars fallback stays for macOS < 14.2 and for a denied permission.

## Setup

- A throwaway app in `spike/process-tap/` (not committed): `main.swift`, `Info.plist`, `build.sh`, `run.sh`.
- `Info.plist`: `CFBundleIdentifier` `dev.opennotch.spike.processtap`, `LSUIElement` true, `NSAudioCaptureUsageDescription` set.
- Built with `swiftc -O` and signed with `codesign --force --sign - --timestamp=none` (ad-hoc, no team).
- Launched with `open -n <app> --args <seconds> <log>`, so macOS treats the app, not a terminal, as the process asking for permission.
- Spotify was playing music. The owner was at the Mac to answer the prompt.

## Calls that worked, in order

All returned status 0.

1. `AudioObjectGetPropertyData` on `kAudioObjectSystemObject`, selector `kAudioHardwarePropertyTranslatePIDToProcessObject`, with Spotify's main PID (from `NSRunningApplication`, bundle id `com.spotify.client`) as the qualifier. This returned a process object; Spotify's main PID owns its audio.
2. `CATapDescription(stereoMixdownOfProcesses: [processObject])`, with `isPrivate = true` and `muteBehavior = .unmuted`.
3. `AudioHardwareCreateProcessTap(desc, &tapID)`.
4. `kAudioTapPropertyUID`, which equals `desc.uuid.uuidString`.
5. `kAudioTapPropertyFormat`: 48 kHz, 2 channels, 32-bit float (`lpcm`, flags 9).
6. `AudioHardwareCreateAggregateDevice` holding only the tap. Keys: `kAudioAggregateDeviceNameKey`, `kAudioAggregateDeviceUIDKey` (a fresh UUID), `kAudioAggregateDeviceIsPrivateKey` true, `kAudioAggregateDeviceTapAutoStartKey` true, and `kAudioAggregateDeviceTapListKey` `[[kAudioSubTapUIDKey: tapUID, kAudioSubTapDriftCompensationKey: true]]`. The device needs no sub-device and no output-device UID.
7. `AudioDeviceCreateIOProcIDWithBlock` on a serial queue. The block computes RMS over the Float32 buffers with no allocations, and stores the latest value and the max under an `os_unfair_lock`.
8. `AudioDeviceStart`.
9. Teardown: `AudioDeviceStop`, `AudioDeviceDestroyIOProcID`, `AudioHardwareDestroyAggregateDevice`, `AudioHardwareDestroyProcessTap`.

## Results

| Run | Binary | Wait before audio started | RMS | CPU |
|---|---|---|---|---|
| 1 | first build | 11 s (aggregate created 17:00:10, IOProc started 17:00:21) | 0.03–0.36, max 0.43 | 0.11–0.22%, 2.45% in the first second |
| 2 | rebuilt and re-signed | 0 s | 0.11–0.29, max 0.41 | ~0.2% |
| 3 | source changed, new CDHash | 4 s | 0.16–0.22, max 0.35 | ~0.2% |

- The IOProc fires with a tap-only private aggregate device. No output sub-device is needed.
- **The prompt.** The wait in run 1 is the call blocking until the owner answered the macOS prompt. The wait in run 3 is a second prompt for the changed binary. The owner confirmed prompts in runs 1 and 3, and none in run 2.
- **Does permission survive a rebuild?** A rebuild that leaves the binary unchanged keeps the permission (run 2). A changed binary asks again (run 3): ad-hoc permission is tied to the binary's code hash. **Consequence:** each new build of OpenNotch from `Scripts/make-app.sh` may ask once more. That is acceptable for a personal build. Settings should show the audio state and offer "Grant" (Task 23).
- **System Settings entry:** not confirmed. The owner's answer did not name the heading, and the permission database is not readable without Full Disk Access. The Task 24 checklist checks where OpenNotch appears under Privacy & Security → Screen & System Audio Recording.
- CPU stayed well under the 3% budget.

## What this changes

- Task 22: use exactly the calls above. Translate Spotify's main PID, or the now-playing app's PID. Use a private tap-only aggregate, and compute RMS/FFT input inside the IOProc without allocating.
- Task 22/23: treat a permission prompt after each rebuild as expected. If the tap delivers silence or fails, show the decorative bars and the "Grant" state.
