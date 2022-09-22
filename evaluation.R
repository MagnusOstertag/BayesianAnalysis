library(brms)
library(caret)
library(yaml)
library(optparse)

source("util.R")

# get the command line arguments
option_list = list(
  make_option(c("-t", "--test"), type = "character", default = "../dataset/2022_08_30/",
              help = "test file path", metavar = "character"),
  make_option(c("-o", "--out"), type = "character", default = "results",
            help = "output folder name", metavar = "character")
);
opt_parser = OptionParser(option_list=option_list);
opt = parse_args(opt_parser);

res_path <- opt$out
test_folder <- opt$test

for (dataset in c("Bounded_artists", "All_artists")) {

  for (type in c("regression", "classification")){

    if (dataset == "classification" && type == "All_artists") {
      next
    }

    search_path = file.path(res_path, dataset, type)

    print(sprintf("Searching for models in %s", search_path))

    # loading the needed test dataframes
    if (type == "classification") {
      test_filename <- sprintf("test_%s.csv", dataset)
    } else {
      test_filename <- sprintf("test_%s_%s.csv", dataset, type)
    }
    test_filepath <- file.path(test_folder, test_filename)
    df_test <- load_dataframe(test_filepath)

    if (type == "classification") {
      # fixing the True false errors
      df_test$hit = factor(as.logical(df_test$hit))
    }
    
    evaluation_frame = data.frame() 
    loo_models = list()
    
    # iterate over models
    for (model_path in list.files(search_path, pattern="fitted", recursive=TRUE)) {
      print(sprintf("Evaluating model in %s", model_path))
      eval_model = list()
      eval_model$dataset = dataset
      eval_model$type = type
      # getting the formula from path (penultimate element in list of path elements)
      eval_model$formula = unlist(strsplit(model_path, '/'))[length(unlist(strsplit(model_path, '/')))-2]
      # getting the prior from path (ultimate element in list of path elements)
      eval_model$prior = unlist(strsplit(model_path, '/'))[length(unlist(strsplit(model_path, '/')))-1]
      
      # reading from model
      fit <- readRDS(file.path(search_path, model_path)) 

      # elapsed times
      elapsed <- rstan::get_elapsed_time(fit$fit)
      warmup <- mean(elapsed[,1])
      sample <- mean(elapsed[,2])
      eval_model$total_time = warmup + sample 

      model_name = paste(eval_model$formula, eval_model$prior)

      # defensive coding then the ll-matrix elimenation does not work
      if (is.null(fit$criteria$loo)){
        res <- calculate_loo_waic(fit)
        loo_models[[model_name]] <- res$fit$criteria$loo
      } else {
        loo_models[[model_name]] <- fit$criteria$loo
      }

      pred <- predict(fit, newdata=df_test)
      
      # if type == classification calcualte accuracy and other metrics else : calculate RMSE,
      if (type == "classification") {
        pred <- pred[, 1] > 0.5
        pred <- factor(pred)

        confusion_matrix <- confusionMatrix(pred, df_test$hit)

        eval_model$sensitivity <- confusion_matrix$byClass['Sensitivity']
        eval_model$specificity <- confusion_matrix$byClass['Specificity']
        eval_model$balanced_accuracy <- confusion_matrix$byClass["Balanced Accuracy"] 
        eval_model$accuracy <- confusion_matrix$overall["Accuracy"] 
         
      }

      else {
        eval_model$RMSE = RMSE(pred, df_test$track_popularity) 
      }
      
      # solving the problem of factorization of the prior columns
      evaluation_frame$prior = as.character(evaluation_frame$prior)
      evaluation_frame <- rbind(evaluation_frame, eval_model)
      evaluation_frame$prior = as.factor(evaluation_frame$prior)
      
    }


    if (length(loo_models) != 0){
      print(sprintf("Exporting models from %s", search_path))
      print(sprintf("Number of loo models found %s", length(loo_models)))
      capture.output(loo_compare(loo_models), file=sprintf("%s_%s_%s.txt", search_path, "loocompare", format(Sys.time(), "%H%M%S")))
      write.csv(evaluation_frame, file=sprintf("%s_%s_%s.txt", search_path, "metrics", format(Sys.time(), "%H%M%S")), row.names=FALSE)
    }
    else{
      print(sprintf("No models from seach path %s", search_path))
    }
     
  }
} 
