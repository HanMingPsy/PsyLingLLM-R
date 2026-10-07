## R CMD check results

The current source tarball passes the local Windows R 4.5.1 check with:

0 errors | 0 warnings | 0 notes

This local run used `R CMD check --as-cran --no-manual` with CRAN incoming
remote checks disabled. Earlier CRAN incoming and Win-builder checks reported
only the expected new-submission NOTE and flagged "Psycholinguistic" and
"psycholinguistic" as possibly misspelled words in DESCRIPTION. Both are
established domain terms that accurately describe the package.

## Test environments

- Local Windows 11, R 4.5.1, `R CMD check --as-cran --no-manual` (current
  source tarball)
- Win-builder Windows Server 2022, R-devel r90539 (earlier 0.4.0 release
  candidate)
- GitHub Actions macOS, R release (earlier 0.4.0 release candidate)
- GitHub Actions Windows, R release (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R-devel (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R release (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R oldrel-1 (earlier 0.4.0 release candidate)

The earlier candidate passed every listed external job, including the
Win-builder PDF and HTML manuals. The exact current source tarball must repeat
the external matrix before this file is used for formal submission. Normal
checks do not use provider credentials or make live model API requests.

## Downstream dependencies

There are no downstream dependencies because this is a new submission.
