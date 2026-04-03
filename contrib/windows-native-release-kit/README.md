# XMDS Windows Native Release Kit

This directory packages the material needed to publish the recent XMDS Windows native compatibility work in a safe and visible way.

It is designed for two use cases:

- a public GitHub repository that showcases the work
- an upstream submission email to the XMDS maintainers

Contents:

- `github-publish-guide-zh.md`: recommended GitHub publishing approach in Chinese
- `publish-checklist-zh.md`: short checklist before publishing
- `windows-native-change-summary-en.md`: English change summary for README or upstream email
- `upstream-email-template-en.md`: ready-to-edit email template for `xmds-devel`
- `README-template-en.md`: starter README for a GitHub repo
- `changed-files.txt`: source files changed in this Windows compatibility effort
- `export_release_bundle.ps1`: copies the changed files and supporting docs into `bundle/`

Notes:

- XMDS is licensed under GPL terms. Keep the original `COPYING` and `COPYRIGHT` files with any redistributed source snapshot.
- This workspace is not a Git or SVN checkout, so this kit exports a clean file bundle rather than a true patch series.
