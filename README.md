# Local OCR for iPhone

The iPhone / iPad sibling of [Local OCR](https://github.com/nakamura196/local-ocr)
(macOS, Windows). It reads the characters in an image **on the device** —
pre-modern Japanese (kuzushiji), modern Japanese print, and multilingual print.
Recognition models are downloaded inside the app the first time you need them;
after that, nothing leaves the device.

By Satoru Nakamura (The University of Tokyo).

[English](#english) · [日本語](#日本語)

## English

### Recognition engines

| Engine | Download | Suited to |
| --- | --- | --- |
| Apple Vision | — (built in) | Modern print and handwriting. Japanese, English, Chinese |
| [NDL Kotenseki OCR Lite](https://github.com/ndl-lab/ndlkotenocr-lite) | 78 MB | Pre-modern Japanese, kuzushiji |
| [NDLOCR Lite](https://github.com/ndl-lab/ndlocr-lite) | 154 MB | Modern Japanese print |
| [PP-OCRv6 medium](https://github.com/PaddlePaddle/PaddleOCR) | 139 MB | Chinese, English, Japanese, Latin-script print |

Model files are pinned to upstream commits (`LocalOCR/Download/ModelCatalog.swift`),
the same files the desktop Local OCR and [KotenOCR](https://github.com/nakamura196/koten-ocr-ios)
use, and their size is checked after download. They are stored in Application
Support and excluded from iCloud backup.

The NDL pipelines are shared with KotenOCR (`LocalOCR/OCR/`). The PP-OCRv6
pipeline is a port of the desktop app's `ppocr` package.

### Development

Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```
xcodegen generate
xcodebuild build -project LocalOCR.xcodeproj -scheme LocalOCR -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild test -project LocalOCR.xcodeproj -scheme LocalOCR -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

`EndToEndTests` downloads all three model sets for real (about 380 MB) and reads the
sample pages in `LocalOCRTests/Resources`; it also runs on a connected iPhone
(`-destination 'id=<UDID>'`). PP-OCRv6 shrinks its detector input to fit the memory
the device has left — see [`docs/notes/iphone-memory.md`](docs/notes/iphone-memory.md).

### Licence

MIT — see [`LICENSE`](LICENSE). The models carry their own terms: the two NDL
models are CC BY 4.0 (National Diet Library, Japan), the PP-OCR models are
Apache-2.0 (PaddlePaddle).

## 日本語

画像に写っている文字を、iPhone・iPad の中だけで読み取るアプリです。
パソコン版 [Local OCR](https://lo.ldas.jp/) の姉妹版です。

くずし字・近代の活字・多言語の活字を読む道具（モデル）は、アプリの「読み取りモデル」の画面から、使うものだけダウンロードします。
Apple Vision はダウンロードなしで使えます。
ダウンロードのあとは、画像も結果も端末の外に送りません。
