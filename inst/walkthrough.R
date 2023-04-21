# Connect to Lobster using your credentials
library(lobsteR)

account_login <- account_login(
  login = Sys.getenv("user"),
  pwd = Sys.getenv("pwd")
)

# Create a request for data from lobster
data_request <- lobsteR:::.request_query(
  symbol = c("BA"),
  start_date = Sys.Date() - 100,
  end_date = Sys.Date() - 98,
  level = 1
) |>
  lobsteR:::.request_validate(account_archive = account_archive)

lobsteR:::.request_submit(account_login = account_login,
                           request_validate = data_request)

# Inspect your archive: Once lobsterdata.com provides your data, you can download
account_archive <- lobsteR:::.account_archive(account_login = account_login)

lobsteR:::.request_download(
  account_login = account_login,
  path = "data",
  id = 333254
)

lobsteR:::.process_collect(path = "data/333254", clean_up = FALSE)

clean_orderbook <- lobsteR:::.process_clean(path = "data/333254")
