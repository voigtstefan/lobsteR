#' Address of the LOBSTER website
#'
#' LOBSTER moved its PHP site, which handles sign-in, requests, the data
#' archive and downloads, to `https://php.lobsterdata.com` in 2026, when
#' `lobsterdata.com` became a new web app. All functions of lobsteR build their
#' addresses with this helper, so a future move needs only the option
#' `lobsteR.base_url`.
#'
#' @param path character(1) Path of a page on the LOBSTER site, e.g.
#'   `"SignIn.php"`. Empty for the base address.
#' @return character(1) The full address.
#' @examples
#' lobster_url("SignIn.php")
#' @export
lobster_url <- function(path = "") {
  base <- getOption("lobsteR.base_url", "https://php.lobsterdata.com")
  paste0(sub("/$", "", base), if (nzchar(path)) "/" else "", path)
}
