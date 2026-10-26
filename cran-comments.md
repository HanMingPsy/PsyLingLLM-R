## Resubmission

This is a resubmission of a new package following the CRAN team's review. The
previous submission was not accepted. In this version I:

- revised the Title and the opening of the Description so that neither starts
  with "Tools for", the package name, or similar wording;
- added a methodologically relevant reference to the Description in the
  requested DOI form;
- added roxygen2 `@return` documentation for every method identified in the
  review, regenerated the corresponding `.Rd` files, and audited every exported
  function for a `\value` section describing the returned class and meaning;
- replaced commented example code with short, executable offline examples;
- changed informational console output to suppressible messages, while keeping
  direct diagnostic output behind the explicit `debug = TRUE` switch; and
- added an offline regression test for suppressing console output.

## R CMD check results

The exact resubmission source tarball passes the complete local Windows R 4.5.1
check with:

0 errors | 0 warnings | 0 notes

This run used `R CMD check --as-cran` with CRAN incoming remote checks disabled.
It included package installation, examples, the complete offline test suite,
and PDF and HTML manual generation. Normal checks do not use provider
credentials or make live model API requests.

An additional `R CMD check --as-cran` run with CRAN incoming remote checks
enabled completed with 0 errors, 0 warnings, and 2 notes:

- "New submission", because PsyLingLLM has not previously been accepted by
  CRAN; and
- "unable to verify current time", because the local runner could not complete
  the external clock comparison.

All package installation, code, documentation, examples, tests, and manual
checks passed in that run.

## Test environments

- Local Windows 11, R 4.5.1, `R CMD check --as-cran` (current source tarball)
- GitHub Actions macOS, R release (current source, commit `de07bfb`)
- GitHub Actions Windows, R release (current source, commit `de07bfb`)
- GitHub Actions Ubuntu, R-devel (current source, commit `de07bfb`)
- GitHub Actions Ubuntu, R release (current source, commit `de07bfb`)
- GitHub Actions Ubuntu, R oldrel-1 (current source, commit `de07bfb`)
- Win-builder Windows Server 2022, R-devel r90539 (earlier 0.4.0 release
  candidate)

All five current-source GitHub Actions jobs passed, including package examples
and tests. The run is available at:
<https://github.com/HanMingPsy/PsyLingLLM-R/actions/runs/40290523985>.
The earlier Win-builder candidate also passed its PDF and HTML manual checks.

## CRAN incoming notes

CRAN incoming spell checking may flag "Psycholinguistic" and
"psycholinguistic". These are established names for the package's scientific
field and are used accurately. It may also flag "Dillion" in the added
reference; this is the correct surname of the cited first author, Danica
Dillion, in <doi:10.1016/j.tics.2023.04.008>.

## Downstream dependencies

There are no downstream dependencies because this is a new submission.
