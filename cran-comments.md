## R CMD check results

0 errors | 0 warnings | 1 note

* This is a new submission.

## Test environments

* local Windows 11, R 4.5.2
* GitHub Actions: ubuntu-latest (release), windows-latest (release), macos-latest (release)

## Notes

* "New submission" note is expected for a first CRAN submission.

* `\dontrun{}` is used in examples for `account_login()`, `account_archive()`,
  `request_submit()`, and `data_download()` because these functions require an
  active LOBSTER account and network access to lobsterdata.com. They cannot be
  run without valid credentials and would fail in any automated check environment.
  Examples that do not require credentials (e.g. `request_query()`) are fully
  runnable.

* There are no published methods or algorithms to cite for this package. It is a
  data-access wrapper around the LOBSTER web service API.

## Downstream dependencies

None (new package).
