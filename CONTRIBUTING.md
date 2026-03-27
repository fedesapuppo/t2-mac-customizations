# Contributing

Thanks for your interest in improving the T2 Mac + Omarchy experience. This repo is a collection of working configuration files and documentation — contributions that help other T2 Mac Linux users are welcome.

## How to Contribute

1. **Fork** this repository
2. **Create a branch** for your change (`git checkout -b my-fix`)
3. **Make your changes** and test them on your T2 Mac
4. **Open a pull request** with a clear description of what changed and why

## What I'm Looking For

### Config improvements
- Fixes or refinements to existing config files
- New config files that solve T2-specific issues not already handled by Omarchy upstream
- Corrections to documentation or outdated information

Before submitting, check whether [Omarchy's T2 support](https://github.com/basecamp/omarchy/blob/master/install/config/hardware/apple/fix-t2.sh) already handles it.

### The big one: suspend/wake

The suspend/wake black screen is the most impactful unsolved problem for T2 Macs on Linux. If you have a workaround — even a partial one — I'd love to hear about it.

That said, some honest context: this issue sits at the intersection of an undocumented T2 chip, a reverse-engineered `apple-bce` driver with no upstream power management support, and a Sonoma firmware regression that Apple will never fix. The T2 Mac developer community is small and shrinking as hardware ages out. A full fix would likely require deep kernel/driver expertise and access to hardware for extended testing. I'm not optimistic, but I'd be thrilled to be proven wrong.

Even if you can't fix it, documenting what you've tried (and what didn't work) is valuable — it saves the next person from repeating the same experiments.

## Guidelines

- **Test on real hardware.** These configs interact with firmware and kernel modules — what works in theory may not work in practice.
- **Document the "why."** A config line without context is hard to evaluate. Explain what problem it solves and on which model you tested it.
- **One concern per PR.** Keep changes focused so they're easy to review and test independently.
- **Keep paths generic.** Some files (like udev rules) may contain hardcoded usernames or paths. Use placeholders or note that they need to be adapted.

## Reporting Issues

If something in this repo doesn't work on your T2 Mac:

1. Open an issue with your **Mac model** (year + type), **kernel version**, and **what happened**
2. Include relevant logs (`journalctl`, `dmesg`) if applicable
3. Note whether you're running Omarchy specifically or another Arch-based distro

## Code of Conduct

Be kind, be helpful, be patient. We're all here because we chose to run Linux on hardware that wasn't designed for it.
