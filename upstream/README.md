# Linux upstream submission workspace

This directory prepares the Razer Phone 2 work for Linux kernel mailing-list
review. It is not a GitHub pull request and it is not yet a send-ready patch
series.

Read `STATUS.md` and `0000-cover-letter-rfc.md` first.

Linux requires each logical change to be split, built, checked and sent inline
with `git send-email`. Devicetree bindings must precede drivers/DTS, and the
board DTS should be last. Use the kernel tree's `scripts/get_maintainer.pl` to
generate recipients.

The human submitter must review every line and add their own `Signed-off-by`
under the Developer Certificate of Origin. AI tools must not add that tag.
