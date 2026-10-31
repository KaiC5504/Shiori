# The Mac loop

A rented Apple-silicon Mac, reached as `ssh macrent` (host entry in `~/.ssh/config`), runs
the same build, screenshots and tests as CI in a few minutes instead of 20. It never holds
signing keys, App Store Connect keys or an Apple ID; TestFlight still ships from Actions.

- `bash tools/mac/run.sh build shots` after each merge; `libtests` and `uitests` as needed,
  or `all`. It pushes local `dev` to `~/Shiori` on the Mac (a plain repo with
  `receive.denyCurrentBranch updateInstead`), never to GitHub.
- Screenshots come back to `.superpowers/mac-shots/<time>/` (gitignored).

Setting up a new rental (once):

1. KaiC pastes `~/.ssh/macrent_ed25519.pub` into the provider, or appends it to the Mac's
   `~/.ssh/authorized_keys` himself, and logs in to the desktop once (the simulator needs
   a GUI session).
2. Xcode 27.1: copy the `.xip` over with `scp`, `xip -x` it, move it to `/Applications`. KaiC
   runs `sudo xcode-select -s`, `sudo xcodebuild -license accept` and
   `sudo xcodebuild -runFirstLaunch` himself, since they need the Mac's password.
3. `xcodebuild -downloadPlatform iOS`, then create the iPhone 17 Pro Max simulator on a
   runtime that accepts it (iOS 27.1 refused it; 27.0 works) and write its UDID to
   `~/sim.udid`.
4. XcodeGen's release zip unpacked into `~/bin/xcodegen`, then
   `git init ~/Shiori && git -C ~/Shiori config receive.denyCurrentBranch updateInstead`
   and `git remote add macrent macrent:Shiori` here.
