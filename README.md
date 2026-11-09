# ReadMeh — Native iOS

ReadMeh is a privacy-first PDF reader and spoken-document player built with SwiftUI, PDFKit, AVFoundation, and MediaPlayer.

## Features in this starter
- Import PDFs from the iOS Files picker.
- Copy documents into the app's private Application Support directory.
- Keep a local library and approximate reading/listening position.
- Extract selectable PDF text locally with PDFKit.
- Speak text with Apple's built-in AVSpeechSynthesizer.
- Provide system voice, speed, and pitch controls.
- Configure spoken-audio background playback and Lock Screen commands.

No account, analytics, ads, tracking SDK, remote inference, or PDF upload is included.

## Build from an iPhone
This repository package includes a GitHub Actions workflow. Upload the project files to a GitHub repository from the GitHub mobile website. Open **Actions → ReadMeh iOS Build → Run workflow**. A hosted macOS runner uses XcodeGen to generate the Xcode project, then compiles an unsigned iOS Simulator app and uploads build logs/artifact.

A simulator artifact is not an installable iPhone IPA. Device installation requires a separate signing and installation step.

## Local build
Requires macOS with Xcode 16+ and XcodeGen:

```sh
brew install xcodegen
xcodegen generate
xcodebuild -project ReadMeh.xcodeproj -scheme ReadMeh -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

## Limitations
- Scanned/image-only PDFs do not contain selectable text; OCR is not implemented yet.
- Narration currently uses iOS system voices, not a bundled neural TTS model.
- Background playback, Lock Screen behavior, and long-document performance must be tested on a physical iPhone.
- This is an initial implementation, not a security-audited release.

## Privacy
PDFs and library metadata are stored locally in the app sandbox. The app has no networking code or third-party SDK dependencies.
