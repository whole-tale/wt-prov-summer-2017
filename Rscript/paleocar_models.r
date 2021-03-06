## YesWorkflow markup!
#@BEGIN  gen_paleocar_model @desc generate paleocar models for predicting the climate for the given years. 
#@in prediction_years @desc period for reconstruction of the paleoclimate using paleocar. 
#@in prism_data_for_coordinates @uri file:.output/{session_id}/{run_id}/112W36N.csv  @desc file containing the precipitation values for the selected region. 

#@param itrdb   @file data/itrdb.Rda
#@param calibration_years @desc period for calibrating the information for predicting the climate. 
#@param min_width @desc min width of the tree rings. 
#@param verbose @desc set to true for writing output to a logfile. 
#@out paleocar_models

paleocar_models <- function(chronologies,
                            predictands,
                            calibration.years,
                            prediction.years = NULL,
                            min_width = NULL,
                            verbose = F,
                            ...){
  if(verbose) cat("Calculating PaleoCAR models\n")
  # cat("...:\n")
  # print(list(...))
  # cat("params:\n")
  # print(list(min_width = min_width,
  #            verbose = verbose))

  # @BEGIN get_predictor_matrix  @desc create a matrix of tree ring chronologies for the calibration year.
  # @IN itrdb 
  # @param calibration_years
  # @PARAM min_width 
  
  # @OUT predictor_matrix 
  # @OUT max_preds
  t <- Sys.time()
  predictor.matrix <- get_predictor_matrix(chronologies = chronologies,
                                           calibration.years = calibration.years,
                                           min_width = min_width)
  # @END get_predictor_matrix
  
  maxPreds <- nrow(predictor.matrix)-5
  
  if(class(predictands) %in% c("RasterBrick","RasterStack")){
    if(nlayers(predictands) != length(calibration.years)){
      stop("Predictand raster must have the same number of layers as the length of the calibration.years vector!")
    }
    null.cells <- which(is.na(raster::getValues(predictands[[1]])))
    predictand.matrix <- t(raster::values(predictands))
    colnames(predictand.matrix) <- as.character(1:raster::ncell(predictands)) 
  } else if(is.vector(predictands)){
    if(length(predictands) != length(calibration.years)){
      stop("Predictand vector must be same length as calibration.years vector!")
    }
    null.cells <- vector(mode = "integer")
    predictand.matrix <- matrix(predictands)
    colnames(predictand.matrix) <- "1"
    rownames(predictand.matrix) <- paste0("X",calibration.years)
  }else if(is.matrix(predictands)){
    if(nrow(predictands) != length(calibration.years)){
      stop("Predictand matrix must have the same number of rows as the length of the calibration.years vector!")
    }
    null.cells <- vector(mode = "integer")
    predictand.matrix <- predictands
    colnames(predictand.matrix) <- 1:ncol(predictand.matrix)
    rownames(predictand.matrix) <- paste0("X",calibration.years)
  }
  
  # @BEGIN get_reconstruction_matrix @desc get reconstruction matrix for chronologies for the prediction year.
  # @IN itrdb  
  # @IN prediction_years 
  # @PARAM min_width
  # @OUT reconstruction_matrix 
  reconstruction.matrix <- get_reconstruction_matrix(chronologies=chronologies, reconstruction.years=prediction.years, min_width=min_width)
  reconstruction.matrix <- reconstruction.matrix[,colnames(predictor.matrix)]
  # @END get_reconstruction_matrix
  
  # @BEGIN get_predlist @desc create list of prediction values. 
  # @IN reconstruction_matrix 
  # @OUT predlist 
  predlist <- get_predlist(reconstruction.matrix)
  # @END get_predlist
  
  prednums <- rowSums(predlist, na.rm=T)
  prednums[prednums > maxPreds] <- maxPreds
  
  predyears <- as.numeric(rownames(predlist))
  hinge.year <- min(predyears[predyears > max(calibration.years)], max(calibration.years))
  
  # @BEGIN get_carscores @desc get the carscores for reconstruction of paleoclimate.
  # @IN prism_data_for_coordinates 
  # @IN predictor_matrix
  # @OUT carscores
    carscores <- carscore_batch(predictand.matrix=predictand.matrix, predictor.matrix=predictor.matrix)
    carscores.ranks <- matrixStats::colRanks(1-(carscores^2), preserveShape=T)
    rownames(carscores.ranks) <- rownames(carscores)
    colnames(carscores.ranks) <- colnames(carscores)
    carscores <- carscores.ranks
    rm(carscores.ranks); gc(); gc()
    carscores <- data.table::data.table(t(carscores))

  # @END getCarscores
  
  if(verbose) cat("\nPrepare data and calculate CAR scores:", round(difftime(Sys.time(),t,units='mins'),digits=2),"minutes\n")
 
  # @BEGIN calculate_Models 
  # @IN predlist
  # @IN carscores
  # @IN max_preds
  # @OUT linear_models
  allModels <- data.table::data.table(cell=numeric(),year=numeric(),model=numeric(),numPreds=numeric(),CV=numeric(),AICc=numeric(),coefs=numeric())
  complete.cell.years <- data.table::data.table(cell=numeric(),year=numeric())
  times <- vector('numeric',max(prednums))
  # @BEGIN defineLinearModels
  # @IN predlist
  # @IN carscores
  # @IN max_preds
  # @OUT models
  # @OUT matches
  for(i in 1:maxPreds){
    if(verbose) cat("\nCalculating models of with",i,"input vectors.")
    t <- Sys.time()
    
    new.t <- Sys.time()
    preds <- predlist[prednums>=i,]
    
    ## MATCHES 1
    matches <- lapply(rownames(preds),function(this.year){
      # cat(this.year,'\n')
      complete.cells <- c(complete.cell.years[year==as.numeric(this.year), cell],null.cells)
      
      pred.names <- colnames(preds)[preds[this.year,]]
      if(all((rownames(carscores) %in% complete.cells))) return(NULL)
      models <- data.table::data.table(matrixStats::rowRanks(as.matrix(carscores[!(rownames(carscores) %in% complete.cells),pred.names,with = F]), ties.method = 'min')<=i)
      data.table::setnames(models,pred.names)
      # which(apply(as.matrix(models),1,function(x){!any(x)}))
      models[,cell:=as.numeric(rownames(carscores)[!(rownames(carscores) %in% complete.cells)])]
      # models <- models[cell %in% which(!completed.cells)]
      data.table::setorderv(models,pred.names,rep(-1,length(pred.names)))
      models.duplicates <- !duplicated(models,by=pred.names)
      models.matches <- cumsum(models.duplicates)
      names(models.matches) <- models$cell
      models.matches <- models.matches[order(as.numeric(names(models.matches)))]
      models <- models[models.duplicates,]
      models[,cell:=NULL]
      blank.models <- !apply(models,2,any)
      blank.models <- names(blank.models)[blank.models]
      if(length(blank.models)>0){
        models[,(blank.models):=NULL]
      }
      # if(any(apply(as.matrix(models),1,function(x){!any(x)}))) error("PROBLEM!")
      return(list(models=models,matches=models.matches))
    })
    gc();gc()
    
    match.names <- rownames(preds)[!sapply(matches,is.null)]
    matches <- matches[!sapply(matches,is.null)]
    
    models <- lapply(matches,'[[','models')
    matches <- lapply(matches,'[[','matches')
    names(matches) <- match.names
    names(models) <- match.names
    
    nummodels <- c(0,cumsum(sapply(models,nrow)))[0-(length(models)+1)]
    names(nummodels) <- names(models)
    
    models <- data.table::rbindlist(models,fill=T)
    pred.names <- sort(names(models))
    data.table::setcolorder(models,pred.names)
    models[,model:=1:nrow(models)]
    
    if(nrow(models)==0) break
    ## Replace all NAs with FALSE (we aren't going to use those predictors, right?)
    for (this.model in seq_along(models)){
      data.table::set(models, i=which(is.na(models[[this.model]])), j=this.model, value=F)
    }
    
    matches <- lapply(1:length(matches),function(count){return(list(year=rep(names(matches)[count],length(matches[[count]])),matches=matches[[count]]+nummodels[count]))})
    
    matches.years <- unlist(lapply(matches,'[[','year'))
    matches.matches <- unlist(lapply(matches,'[[','matches'))
    
    matches <- do.call(rbind,list(cell=as.integer(names(matches.matches)),year=as.integer(matches.years),model=as.integer(matches.matches)))
    colnames(matches) <- NULL
    matches <- data.table::data.table(t(matches))
    
    rm(matches.years, matches.matches)
    gc();gc()
    
    models <- data.table::setorderv(models,pred.names,rep(-1,length(pred.names)))
    models.duplicates <- !duplicated(models,by=pred.names)
    models.matches <- cumsum(models.duplicates)
    names(models.matches) <- models$model
    models.matches <- models.matches[order(as.numeric(names(models.matches)))]
    models <- models[models.duplicates,]
    models[,model:=NULL]
    models.matches <- data.table::data.table(model=as.integer(names(models.matches)),new.model=models.matches)
    
    setkey(matches,model)
    setkey(models.matches,model)
    
    matches <- matches[models.matches]
    matches[,model:=NULL]
    setnames(matches,c('cell','year','model'))
    matches <- data.table::setorderv(matches,c('cell','year','model'),c(1,1,1))
    
    rm(models.duplicates,models.matches); gc(); gc()
    
    if(nrow(complete.cell.years)>0){
      which.matches <- merge(matches,complete.cell.years,by=c("cell","year"), all.x=T)[is.na(model.y)]
      matches <- which.matches[,list(cell,year,model.x)]
      setnames(matches,c("cell",'year','model'))
    }
    
    setkey(matches,model)
    # @END defineLinearModels
    if(verbose) cat("\nDefine models:", round(difftime(Sys.time(),new.t,units='mins'),digits=2),"minutes")
    # @BEGIN calculateLinearModels
    # @IN models
    # @IN matches
    # @OUT coefficients
    # @OUT model_errors
    new.t <- Sys.time()
    all.lms <- lapply(1:nrow(models),function(this.model){
      # cat(this.model,'\n')
      if(!(this.model %in% matches[['model']])) return(NULL)
      cells <- unique(matches[list(this.model),cell])
      
      predictand.names <- names(models[this.model])[which(as.logical(models[this.model]))]
      model.mlm <- lm(predictand.matrix[,cells,drop=F]~predictor.matrix[,predictand.names,drop=F])
      
      # Get model errors
      model.errors <- data.table::data.table(CV_mlm(model.mlm))
      model.errors[,cell:=cells]
      
      data.table::setkey(model.errors,cell)
      
      # Get coefficients
      
      coefs <- data.table::data.table(t(as.matrix(model.mlm$coefficients)))
      data.table::setnames(coefs,c("Intercept",colnames(predictor.matrix[,predictand.names,drop=F])))
      coefs <- lapply(1:nrow(coefs),function(j){
        out <- as.numeric(coefs[j])
        names(out) <- colnames(coefs)
        return(out)
      })
      names(coefs) <- cells
      
      coefs <- coefs[order(as.integer(names(coefs)))]
      
      if(length(coefs)==1){
        model.errors[,coefs:=list(coefs)]
      }else{
        model.errors[,coefs:=coefs]
      }
      model.errors[,model:=this.model]
      data.table::setcolorder(model.errors,c("cell","model","CV","AICc","coefs"))
      data.table::setkey(model.errors,cell,model)
      
      return(model.errors)
    })
    all.lms <- all.lms[!sapply(all.lms,is.null)]
    if(verbose) cat("\nCalculate",length(all.lms),"linear models:", round(difftime(Sys.time(),new.t,units='mins'),digits=2),"minutes")
    rm(models); gc(); gc()
    # @END calculateLinearModels
    
    # @BEGIN simplifyLinearModels
    # @IN coefficients
    # @IN model_errors
    # @OUT final_models @as linear_models
    ## LMS SIMPLIFY PREP
    new.t <- Sys.time()
    
    all.lms <- data.table::rbindlist(all.lms,fill=T)
    setkey(all.lms,cell,model)
    all.lms[,numPreds:=i]
    
    if(nrow(allModels)==0){
      data.table::setkey(all.lms,cell,model)
      data.table::setkey(matches,cell,model)
      allModels <- matches[all.lms]
      
      setcolorder(allModels,c("cell","year","model","numPreds","CV","AICc","coefs"))
    }
    
    all.lms.stats <- all.lms[,list(cell,model,AICc)]
    setkey(all.lms.stats,cell,model)
    setkey(matches,cell,model)
    
    all.lms.stats <- matches[all.lms.stats]
    rm(matches)
    
    data.table::setkey(all.lms.stats,cell,year,model)
    
    allModels.stats <- allModels[,list(cell,year,model,AICc)]
    
    allModels.stats <- rbind(allModels.stats,all.lms.stats,fill=T)
    
    data.table::setkey(allModels.stats,cell,year)
    data.table::setorder(allModels.stats,cell,year,AICc)
    allModels.stats <- allModels.stats[allModels.stats[,!duplicated(year),by=cell]$V1,]
    
    data.table::setkey(allModels,cell,year,model)
    if(nrow(allModels.stats[model==0,list(cell,year,model)])>0){
      allModels.old <- merge(allModels.stats[model==0,list(cell,year,model)],allModels,by=c("cell","year","model"), all=T)
    }else{
      allModels.old <- data.table(cell=numeric(),year=numeric(),model=numeric(),numPreds=numeric(),CV=numeric(),AICc=numeric(),coefs=numeric())
    }
    
    if(nrow(allModels.stats[model!=0,list(cell,year,model)])>0){
      allModels.new <- merge(allModels.stats[model!=0,list(cell,year,model)],all.lms.stats,by=c("cell","year","model"), all=T)
      allModels.new <- merge(allModels.new[,list(cell,year,model)],all.lms,by=c("cell","model"),all=T)
      data.table::setcolorder(allModels.new,c("cell","year","model","numPreds","CV","AICc","coefs"))
    }else{
      allModels.new <- data.table::data.table(cell=numeric(),year=numeric(),model=numeric(),numPreds=numeric(),CV=numeric(),AICc=numeric(),coefs=numeric())
    }
    
    allModels <- rbind(allModels.old,allModels.new)
    
    data.table::setkey(allModels,cell,year)
    data.table::setorder(allModels,cell,year,AICc)
    allModels <- allModels[allModels[,!duplicated(year),by=cell]$V1,]
    
    complete.cell.years <- allModels[model==0,list(cell,year,model)]
    
    allModels[,model:=0]
    
    setkey(allModels,cell,year,numPreds)
    
    if(verbose) cat("\nClean linear models:", round(difftime(Sys.time(),new.t,units='mins'),digits=2),"minutes")
    # @END simplifyLinearModels
    
    time <- difftime(Sys.time(),t,units='mins')
    if(verbose) cat("\nTotal modeling time:",round(time,digits=2),"minutes\n")
    times[i] <- time
    if((nrow(allModels)-nrow(complete.cell.years))==0) break
    if(verbose) cat(nrow(allModels)-nrow(complete.cell.years),"cell-years remaining\n")
    ## 
    
  }
  
  if(verbose) cat("\nTotal Modeling Time:",sum(times),"minutes\n")
  # @END calculate_Models
  
  # @BEGIN optimizeModels
  # @IN linear_models
  # @OUT paleocar_models 
  t <- Sys.time()
  get.coef.names <- function(year,model,coefs,numPreds,CV,AICc){
    the.coefs <- lapply(coefs,function(x){names(x)[-1]})
    test.out <- lapply(the.coefs,function(x){which(rowSums(predlist[,x,drop=F])==length(x))})
    test.out <- data.table::data.table(model=rep(1:length(test.out),times=sapply(test.out,length)), year=unlist(test.out))
    # test.out <- lapply(1:length(test.out),function(i){data.table(model=i,year=test.out[[i]])})
    # test.out <- rbindlist(test.out)
    test.out <- test.out[which(!duplicated(test.out[,year]))]
    setkey(test.out,year)
    return(list(year=sort(year),model=model[test.out$model],numPreds=numPreds[test.out$model],CV=CV[test.out$model],AICc=AICc[test.out$model],coefs=coefs[test.out$model]))
  }
  
  allModels <- allModels[order(AICc)][,get.coef.names(year,model,coefs,numPreds,CV,AICc),by=cell]
  setkey(allModels,cell,year)
  
  allModels <- allModels[allModels[,!FedData::sequential_duplicated(CV),by=cell]$V1,]
  
  time <- difftime(Sys.time(),t,units='mins')
  if(verbose) cat("\nOptimizing models:",round(time,digits=2),"minutes\n")
  
  allModels <- list(models = allModels, 
                    predictands = predictands, 
                    predictor.matrix = predictor.matrix, 
                    reconstruction.matrix = reconstruction.matrix, 
                    carscores = carscores)
  
  # @END optimizeModels
  return(allModels)
  # @END gen_paleocar_model
}

