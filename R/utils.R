hash_object <- function(x) {
  digest::digest(x)
}

exists0 <- function(name, envir) {
  exists(name, envir, inherits=FALSE)
}

rm0 <- function(list, envir) {
  del <- exists0(list, envir)
  rm(list=list[del], envir=envir)
  del
}