---
layout: post
title: Dipping Into RHIPE
tags: [rhwatch, map]
summary: In this first post of the RHIPE blog, I introduce to the reader some basic commands.
---

<!-- * mytoc -->
<!-- {:toc} -->

In this first post of the RHIPE blog, I introduce to the reader some basic
commands. These commands should illustrate how to submit jobs via RHIPE, monitor
it's execution and retrieve results.

## Setting Some Useful Options via `rhoptions`

	options(java.parameters="-Xrs")

	rhoptions(HADOOP.TMP.FOLDER	= sprintf(path-to-user-specified-temp-folder-on-hdfs),
		job.status.overprint	= TRUE,
		write.job.info		= TRUE)
	
			

The above options in order

`java.parameters="-Xrs"`
: RHIPE requires rJava. Interrupting control in the R console via `CTRL-C`
causes R to quit immediately. Setting this option prevents that. Very useful.

`HADOOP.TMP.FOLDER`
: a location e.g. `/user/sguha/tmp` on the HDFS. RHIPE will use this to create
temporary files. You really need to define one.

`job.status.overprint`
: when job output is displayed in the console, instead of scrolling through the
window, the status will be displayed over the previous output.

`write.job.info`
: the job info(number of records processed, number saved, time taken etc) will
be saved in the output folder

## Initialize RHIPE

This is the first thing, type

	rhinit()


## Can You Browse the HDFS?

`rhls` takes a path on the HDFS and returns a data frame similar to `ls` on UNIX
systems. You can replace `rhoptions()$HADOOP.TMP.FOLDER` with any path on the
HDFS e.g. `/`.

	rhls(rhoptions()$HADOOP.TMP.FOLDER)

## Your First Job

Let's try and compute pi via a monte carlo simulation. We'll do it in R, via the
`parallel` library. Code is taken from [here](http://www.mathworks.com/products/parallel-computing/examples.html?file=/products/demos/shipping/distcomp/paralleldemo_parfor_pi.html)

	R <- 1
	R2 <- R^2
	N <- 1e6
	PI <- function(r){
	  x <- R*runif(2)
	  sum(x*x)<=R2
	}
	total <- mclapply(1:N,PI)
	sum(unlist(total))*4/N

The RHIPE version would be

	R <- 1
	R2 <- R^2
	N  <- 1e6
	total <- rhwatch(function(key,value){
	  rhcollect(1L,PI(value))
	}
	                 ,reduce=rhoptions()$templates$scalarsummer,
	                 ,input=N,read=FALSE)
	
If the job succeeds, then `total` will contain information about the job. Type
`total` in your R console. It contains information about the counters, time
taken to run, and the configuration that went into creating the job.

### Getting Back the Results
If however, `read=TRUE` (the default), then the sum is read back into
`total`. Since we have set `read=FALSE` we have to read it:

	total <- rhread(total)

And then our estimate of pi is `total[[1]][[2]]*4/N`.

## Your Second Job: Creating Text Data
Taken from the mailing list (see
[this thread](https://groups.google.com/d/msg/rhipe/ovPooyYOIxE/936iCkXVxigJ))

We need to generate some fake data as this

	05,WMB,02064934-5360-4f06-aadb-6d44f862b016,30.76,30.75,35,14,2012-05-16 14:48:33:173
	52,XOM,7c9a6373-4910-4ec5-bf0a-d95d0fbf3994,82.5,82.5,7,31,2012-05-16 14:48:33:174
	52,XOM,5d91d383-ab6e-4961-884e-0f6ba813eb19,82.5,82.5,7,14,2012-05-16 14:48:33:175
	52,XOM,3658e7dc-258d-412a-9c4f-27ae19b57fa1,82.51,82.5,7,14,2012-05-16 14:48:33:176
	52,XOM,200d9e36-827b-431c-b487-34ab2b224639,82.51,82.5,8,14,2012-05-16 14:48:33:177

This code will generate 387MB of text that looks like the above

	xtime <- as.character(Sys.time())
	map <- expression({
	  for(x in map.values)
	    rhcollect(NULL,
	              paste(sample(1:100,1),
	                    paste(sample(letters,3),collapse=""),
	                    paste(sample(letters,36,replace=TRUE),collapse=""),
	                    runif(1),runif(1),runif(1),runif(1),xtime,sep=",",collapse=","))
	})
	
	datMat <- rhwatch(map=map,reduce=1, input=c(3000000,50)
	                  ,output=rhfmt(type='text',folders="/user/sguha/tmp/txt",writeKey=FALSE)
	                  ,read=FALSE)

We need to compute some information for a linear regression(again, see the above
thread for context)

	map<- expression({
	  datMat<- do.call("rbind", strsplit(unlist(map.values),","))
	  datMat <- t(apply(datMat[,c(4,5,6,7)],1,as.numeric))
	  yMat<- as.matrix(datMat[,1])
	  datMat<- cbind(1, as.matrix(datMat[, c(2,3,4)]))
	
	  val1 <- crossprod(datMat, datMat)
	  val2 <- crossprod(datMat, yMat)
	  rhcollect("temp_out",cbind(val1,val2))
	})
	
	reduce<- expression(
	    pre = { .sum <- 0},
	    reduce = { for(x in reduce.values) .sum <- .sum +x},
	    post={
	      if(.rhipe.current.state == "map.combine"){
	        rhcollect( reduce.key, .sum)
	      }else{
	        x <- .sum[, -dim(.sum)[2]]
	        y <- .sum[,  dim(.sum)[2]]
	        betas <- solve(as.matrix(x), as.matrix(y))
	        rhcollect("betas", betas)
	      }
	    })
	
	z <- rhwatch(map=map,reduce=reduce,combine=TRUE
	             ,input=rhfmt("/user/sguha/tmp/txt",type='text')
	             ,jobname = "Rhipe_OLS",mapred=list(mapred.reduce.tasks=1))
	
	
## Counting Words
We need to count unique symbols occurring in the 2nd column of the above fake
data.

	map<- expression({
	  datMat<- do.call("rbind", strsplit(unlist(map.values),","))
	  sapply(datMat[,2],function(a) rhcollect(a,1))
	})
	
	uniqueCount <- rhwatch(map=map ,reduce=rhoptions()$templates$scalarsummer
	                       ,input=rhfmt("/user/sguha/tmp/txt",type='text')
	                       ,jobname = "SymbolCount")
