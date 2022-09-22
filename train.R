library(yaml)
library(brms)
library(ggplot2)
library(Hmisc)
library(dplyr)
library(caTools)
library(yardstick)
library(optparse)

source("util.R")

# get the command line arguments
option_list = list(
  make_option(c("-c", "--config"), type = "character", default = "input_par.yml",
              help = "configuration file name", metavar = "character"),
  make_option(c("-o", "--out"), type = "character", default = "results",
            help="output folder name", metavar="character"),
  make_option(c("-f", "--force"), type="logical", default=TRUE, 
            help="whether to overwrite existing models", metavar="logical")
);
opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

res_path <- opt$out

# loading the input parameter file
input_p <- yaml.load_file(opt$config)

res_path <- file.path(res_path, input_p$type_of_dataset)
print(sprintf("Training on %s", input_p$type_of_dataset))

# loading the needed dataframes
df <- load_dataframe(input_p$train_file)
df_test <- load_dataframe(input_p$test_file)

for (conf in input_p$train_configurations) {

  # a bit of preprocessing from True False python to R TRUE FALSE
  if (conf$type == "classification") {
    df_test$hit = factor(as.logical(df_test$hit))
    df$hit = factor(as.logical(df$hit))
  }

  # catch if a configuration produces an error
  tryCatch(
    {
    print(sprintf("Using this configuration: %s", conf))
    path_type <- file.path(res_path, conf$type)
    
    formula <- formula(conf$formula)

    if (conf$type == "classification"){
      family <- brmsfamily(conf$family, link = conf$link)
    }
    # case regression
    else {
      family <- brmsfamily(conf$family)
    }

    path_model <- file.path(path_type, conf$formula_str)

    if (dir.exists(path_model) == TRUE) {
      if (opt$force) {
        print(sprintf("Warning: Removing folder %s", path_model))
        unlink(path_model, recursive = TRUE)
      } else {
        print(sprintf("Skipping the model at %s", path_model))
        next
      }
    }
    
    print(sprintf("Using the following path: %s", path_model))
    dir.create(path_model, recursive=TRUE)

    for (prior in conf$priors){

      print(sprintf("Using this prior: %s for formula %s", prior, conf$formula))

      path_prior = file.path(path_model, prior)

      dir.create(path_prior, recursive=TRUE)
      fit <- brm(formula,
                data = df,
                family = family,
                chains = input_p$chains,
                cores = input_p$cores,
                seed = input_p$seed,
                prior = set_prior(prior),
                save_model = file.path(path_prior, "stan"),
                file = file.path(path_prior, "fitted"),
                save_pars = save_pars(all = TRUE))
      res <- calculate_loo_waic(fit)

      # make a logging for bad_indices
      print(sprintf("Bad indices %d", res$bad_indices))
      
      # save the model
      saveRDS(res$fit, file=file.path(path_prior, "fitted.rds"))

      # save model summary
      capture.output(fit, file=file.path(path_prior, "model_summary.txt"))
      
      # plotting the performance of the model
      
      # chains
      plot(fit, ask = FALSE)
      ggsave(file.path(path_prior, "chains.png"))
      
      # posterior hist plot
      pp_check(fit, 
              type = "error_hist",
              ndraws = 40)
      ggsave(file.path(path_prior, "pp_check_hist.png"))
    
      # posterios dens plot
      pp_check(fit, 
              type = "dens_overlay",
              ndraws = 500)
      ggsave(file.path(path_prior, "pp_check_dens.png"))
    
      # prior checks
      prior_fit <- brm(formula,
                data = df,
                family = family,
                chains = input_p$chains,
                cores = input_p$cores,
                seed = input_p$seed,
                prior = set_prior(prior),
                save_pars = save_pars(all = TRUE),
                sample_prior = "only",)
    
      # prior hist plot
      pp_check(prior_fit, 
              type = "error_hist",
              ndraws = 20)
      ggsave(file.path(path_prior, "prior_check_hist.png"))

      # prior dens plot
      pp_check(prior_fit, 
              type = "dens_overlay",
              ndraws = 500)
      ggsave(file.path(path_prior, "prior_check_dens.png"))

      # train confusion matrix
      
      # adding to dataframe for better framework support
      if (conf$type == "classification"){
        pred <- predict(fit)
        df$predictions = pred[, 1] > 0.5
        df$predictions = factor(df$predictions)
        # confusion matrix test data or scatter if regression
        conf_matrix = conf_mat(data=df, truth=hit, estimate=predictions) 
        autoplot(conf_matrix, type = "heatmap") +
          scale_fill_gradient(low="#D6EAF8",high = "#2E86C1")
        ggsave(file.path(path_prior, "confusion_matrix_train.png"))
        
        # test confusion matrix
        pred <- predict(fit, newdata=df_test)
        
        # adding to dataframe for better framework support
        df_test$predictions = pred[, 1] > 0.5
        df_test$predictions = factor(df_test$predictions)
        
        print(typeof(df_test$predictions))
        
        # confusion matrix test data or scatter if regression
        conf_matrix = conf_mat(data=df_test, truth=hit, estimate=predictions) 
        autoplot(conf_matrix, type = "heatmap") +
          scale_fill_gradient(low="#D6EAF8",high = "#2E86C1")
        ggsave(file.path(path_prior, "confusion_matrix_test.png"))
      }
      
      # for regression
      else {

        # scatter plot training data
        pred <- predict(fit)
        df$predictions = pred[, 1] 
        ggplot(df, aes(x=df$predictions, y=df$track_popularity)) +
           geom_point() + 
           labs(x="predictions", y="track popularity") +
           ggtitle("Scatter plot for training data") 
        ggsave(file.path(path_prior, "scatter_plot_train_data.png"))
        
        # scatter plot test data
        pred <- predict(fit, newdata=df_test)
        df_test$predictions <- pred[, 1]
        ggplot(df_test, aes(x=df_test$predictions, y=df_test$track_popularity)) +
          geom_point() + 
          labs(x="predictions", y="track popularity") + 
          ggtitle("Scatter plot for training data")
        ggsave(file.path(path_prior, "scatter_plot_test_data.png"))
        
      }

      
      # calculate uncertainty for each of the features and predictions (use marginal effect or conditional effects)
    }

  },
  error = function(cond) {
    print(sprintf("WARNING: this configuration produced an error: %s", conf))
    print(cond)
    print(sprintf("WARNING: deleting all models of this type... %s", path_type))
    unlink(path_type, recursive = TRUE)
  })
}
