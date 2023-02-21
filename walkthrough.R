account_login <- lobsteR:::.account_login(
  login = "a01627386@unet.univie.ac.at",
  pwd = rstudioapi::askForPassword("Account password")
)

account_archive <- lobsteR:::.account_archive(account_login = account_login)

request_validate <- lobsteR:::.request_query(
  symbol = "TSLA",
  start_date = Sys.Date() - 20,
  end_date = Sys.Date(),
  level = 1L
) %>%
  lobsteR:::.request_validate(account_archive = account_archive)

lobsteR:::.request_execute(account_login = account_login, request_validate = request_validate)

a <- lobsteR:::.request_download(
  account_login = account_login,
  account_archive = account_archive,
  path = getwd(),
  id = 332757L
)

lobsteR:::.process_cbind(path = 332757L)
