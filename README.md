# 3FDragUnstuck

A tiny macOS menu bar app for reducing the release delay after three-finger drag.

After a three-finger drag, macOS can keep the drag active for a short moment after your fingers leave the trackpad. This makes drag-and-drop, selection rectangles, and quick follow-up clicks feel stuck.

This app watches trackpad contact counts. When a touch sequence peaks at exactly three fingers and then all fingers are released, it posts one `leftMouseUp` event at the current pointer position.

## Install

Download the latest release:

https://github.com/ddugel3/3FDragUnstuck/releases/latest

Then:

1. Unzip `3FDragUnstuck.app`.
2. Move it to `/Applications`.
3. Open it. If macOS blocks it, right-click the app and choose Open.
4. Click the `3F` menu bar item and choose `Request Accessibility Permission`.
5. Enable it in System Settings > Privacy & Security > Accessibility.
6. Quit and reopen the app if the permission does not apply immediately.

## Build

```sh
make build
```

The app is created at `build/3FDragUnstuck.app`.

To run it locally:

```sh
open build/3FDragUnstuck.app
```

To create a release zip:

```sh
make release
```

## How It Works

- Loads Apple's private `MultitouchSupport` framework at runtime.
- Registers a contact frame callback for every multitouch device returned by `MTDeviceCreateList`.
- Tracks the highest contact count in the current touch sequence.
- Posts one `kCGEventLeftMouseUp` when the sequence reaches zero active contacts.

It sends `leftMouseUp`, not a full click. The goal is to end a stuck drag without creating a new click.

## Notes

- Known working on macOS Tahoe 26.4.1.
- Apple Silicon only for now.
- Not notarized.
- Uses private macOS APIs, so macOS updates can break it.
- Requires Accessibility permission.
