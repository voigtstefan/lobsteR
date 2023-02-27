account_login <- lobsteR:::.account_login(
  login = "a01627386@unet.univie.ac.at",
  pwd = rstudioapi::askForPassword("Account password")
)

account_archive <- lobsteR:::.account_archive(account_login = account_login)

request_validate <- lobsteR:::.request_query(
  symbol = "TSLA",
  start_date = Sys.Date() - 20,
  end_date = Sys.Date() - 20,
  level = 10L
) %>%
  lobsteR:::.request_validate(account_archive = account_archive)

lobsteR:::.request_execute(account_login = account_login, request_validate = request_validate)

a <- lobsteR:::.request_download(
  account_login = account_login,
  path = getwd(),
  id = 332832L
)

lobsteR:::.process_cbind(path = as.character(332832L), clean_up = FALSE)
