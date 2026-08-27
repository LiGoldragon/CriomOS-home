# Upstream notices

This repository adapts the package expressions and narrowly selected update
flows below.  The source revisions are immutable so that the provenance of
the adapted code remains reviewable.

The corresponding pinned nixpkgs maintainer metadata is preserved where a
valid `lib.maintainers` handle exists.  The `claude-code` package maps to
`adeci`, `markus1189`, `mirkolenz`, `omarjatoi`, `oskarwires`, and
`xiaoxiangmoe`; `chatgpt` maps to `wattmto`.  The pinned nixpkgs has no
`claude-desktop` maintainer attribute.  The upstream `claude-code` list also
contains Malo Bourgon (`malob`), which is retained here as attribution but is
not invented as a nixpkgs handle.

## Numtide llm-agents.nix

Adapted files include the four owned package expressions, their hash layouts,
the platform/fetch helpers, and the four package-specific update flows.  The
source revision is
[`76b78a399417964e9133aed0c0a9493616c3508e`](https://github.com/numtide/llm-agents.nix/tree/76b78a399417964e9133aed0c0a9493616c3508e).

The Codex and Claude Code updaters discover release metadata over HTTPS and
then record immutable Nix hashes in the checkout; that transport is not
represented as a repository signature and these flows do not silently claim
one.  ChatGPT and Claude Desktop instead require their vendored archive key,
the recorded fingerprint, and the official signed Release/InRelease chain
before accepting package-index or archive changes.  A key or signer change is
an explicit trust-boundary change, not an automatic update.

```text
MIT License

Copyright (c) 2024 Numtide

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Mic92/formatelf

`lib/formatelf.nix` and its setup-hook boundary are adapted from
[`2b36d819b48c0bfd4a084e6f0ce430633d8ee5f4`](https://github.com/Mic92/formatelf/tree/2b36d819b48c0bfd4a084e6f0ce430633d8ee5f4).

```text
MIT License

Copyright (c) 2026 Jörg Thalheim

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Mic92/wrap-buddy

`packages/wrap-buddy/default.nix` is adapted from
[`ba5ab56ddc572482c26b2cf08414befc5f66ad40`](https://github.com/Mic92/wrap-buddy/tree/ba5ab56ddc572482c26b2cf08414befc5f66ad40).

```text
MIT License

Copyright (c) 2026 Jörg Thalheim and contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
