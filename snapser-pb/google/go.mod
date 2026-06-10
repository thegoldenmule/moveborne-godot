// Quarantine marker, not a real module: google/api mixes three Go packages
// (annotations, httpbody, visibility) in one directory, so it can never build
// as part of the snapser-pb module. The generated snap stubs import the
// canonical upstream packages (google.golang.org/genproto/...) instead — these
// vendored copies are reference-only. This nested go.mod excludes the subtree
// from `go build ./...` at the snapser-pb root.
module snapser-pb/google

go 1.26
