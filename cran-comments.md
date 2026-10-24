## Resubmission

This is a resubmission addressing the CRAN team's review. In this version I:

- revised the Title and the opening of the Description so that neither starts
  with "Tools for", the package name, or similar wording;
- added a methodologically relevant reference to the Description in DOI form;
- documented the return value and its meaning for every method identified in
  the review;
- replaced commented example code with short, executable offline examples;
- changed informational console output to suppressible messages; and
- added an offline regression test for suppressing console output.

## R CMD check results

The exact source tarball submitted passes the complete local Windows R 4.5.1
check with:

0 errors | 0 warnings | 0 notes

This run used `R CMD check --as-cran` with CRAN incoming remote checks disabled.
It included package installation, examples, the complete offline test suite,
and PDF and HTML manual generation. Normal checks do not use provider
credentials or make live model API requests.

## Test environments

- Local Windows 11, R 4.5.1, `R CMD check --as-cran` (current source tarball)
- Win-builder Windows Server 2022, R-devel r90539 (earlier 0.4.0 release
  candidate)
- GitHub Actions macOS, R release (earlier 0.4.0 release candidate)
- GitHub Actions Windows, R release (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R-devel (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R release (earlier 0.4.0 release candidate)
- GitHub Actions Ubuntu, R oldrel-1 (earlier 0.4.0 release candidate)

The earlier candidate passed every listed external job, including the
Win-builder PDF and HTML manuals. The exact resubmission tarball has not yet
repeated the external matrix.

## Downstream dependencies

There are no downstream dependencies because this is a new submission.
