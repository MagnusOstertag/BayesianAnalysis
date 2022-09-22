library(brms)

load_dataframe <- function(f) {
  # loading the dataframe
  df <- read.csv(f)
  print(sprintf("Loaded dataset %s with %d rows", f, nrow(df)))

  return (df)
}

calculate_loo_waic <- function(fit){

  # check whether there are infinite entries in lik
  bad_indices <- c()
  counter <- 0
  lik <- log_lik(fit)
  for (j in seq_along(lik[1,])) {
    if (sum(is.infinite(as.matrix(lik[,j]))) > 0){
      print(sprintf("Bad entries in the log lik detected! %s", j))
      bad_indices <- c(bad_indices, j)
      counter <- counter + 1
    }
  }

  if (counter == 0) {
    fit <- add_criterion(fit, criterion = c("waic", "loo"))
  } else {
    lik <- lik[, -bad_indices]
    loo_fit <- loo(lik)
    waic_fit <- waic(lik)

    fit$criteria$loo <- loo_fit
    fit$criteria$waic <- waic_fit
  }

  res <- list("fit" = fit, "bad_indices" = bad_indices)

  return(res)
}
