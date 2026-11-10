> Historical coverage or experiment record: current release validation runs on Mac Studio; see [LocalRelease.md](../Development/LocalRelease.md). Prior results and limitations remain recorded below.

# Sequential reviewed-import coverage

`SequentialImportRestartTests.fourRoutes` is an additive integration candidate.
It saves direct, step-parent, child and current-partner imports into one synthetic
notebook. After each save it closes and reopens the store, checks every saved
identity, listed state and all-people visibility, and checks the precise endpoints
and types of every relationship created so far. It also checks the complete
person and relationship snapshots and counts after every reopen.

This is not an app relaunch or an end-to-end UI test: it does not open any
entry-point screen, drive review, selection or save controls, present the native
Contacts picker, or verify that the next UI route opens after a process restart.
The existing four-route UI sequence and its intermediate restarts remain in
place. The separate native Contacts journey also remains required. This test
is a candidate until it executes successfully in the actual KinTests target;
syntax checking alone does not establish that it passes.
