## ---
## title: "storr"
## author: "Rich FitzJohn"
## date: "`r Sys.Date()`"
## output: rmarkdown::html_vignette
## vignette: >
##   %\VignetteIndexEntry{storr}
##   %\VignetteEngine{knitr::rmarkdown}
##   \usepackage[utf8]{inputenc}
## ---

library(storr)

## `storr` provides very simple key/value stores for R.  They attempt
## to provide the most basic set of key/value lookup functionality
## that is completely consistent across a range of different
## underlying storage drivers (in memory storage, filesystem and
## proper databases).  All the storage is _content addressable_, so
## keys map onto hashes and hashes map onto data.

## The `rds` driver stores contents at some path by saving out to rds
## files.  Here I'm using a temporary directory for the path; the
## driver will create a number of subdirectories here.
path <- tempfile("storr_")
st <- storr::storr_rds(path)

## Alternatively you can create the driver explicitly:
##+ eval=FALSE
dr <- storr::driver_rds(path)

## With this driver object we can create the `storr` object which is
## what we actually interact with:
##+ eval=FALSE
st <- storr::storr(dr)

## ## Key-value store

## The main way of interacting with a `storr` object is
## `get`/`set`/`del` for getting, setting and deleting data stored at
## some key.  To store data:
st$set("mykey", mtcars)

## To get the data back
head(st$get("mykey"))

## What is in the `storr`?
st$list()

## Or, much faster, test for existance of a particular key:
st$exists("mykey")

st$exists("another_key")

## To delete a key:
st$del("mykey")

## It's gone!
st$list()

## though the actual data is still stored in the database:
h <- st$list_hashes()
h

## The hash of an object is computed using the `digest` package, and
## can be done using the `hash_object` method of the storr.
st$hash_object(mtcars)

## An object can be retrieved directly given its hash:
head(st$get_value(h))

## similarly, we can test to see if an object is present in the
## database using its hash:
st$exists_object(h)

## though now that there are no keys pointing at the data is is
## subject to garbage collection:
del <- st$gc()
del

st$list_hashes()

## ## Namespaces

## At some point having everything stored in a great big bucket may
## become too instrucured.  To help with this storr implements a very
## simple "namespace" system that may help provide some structure.  It
## is a single layer of hierarchy above keys; so every key belongs to
## a namespace.  The default namespace is "objects" but this can be
## configured when the storr is created.
st$default_namespace

## The `list_namespaces()` method lists all known namespaces
st$list_namespaces()

## To create a new namespace, simply assign an object into it:
st$set("a", runif(5), namespace = "other_things")
st$list_namespaces()

## The `list()` method lists the contents of a single namespace
st$list()
st$list("other_things")

## To get an object, you must use the correct namespace:
##+ error = TRUE
st$get("a")
st$get("a", "other_things")

## ## Bulk get/set

## If you have many values to get or set, for some databases it will
## be much more efficient to get and set them in bulk; this is
## particularly the case with high-latency database (e.g., anything
## over a network connection, especially an internet connection).  To
## help with this, storr implements `mget` and `mset` methods that
## allow multiple values to retrieved or set.

## The `mset` function allows multiple keys (and/or multiple
## namespaces) and multiple data elements.  The data must have the
## same `length()` as the number of keys being set.
st$mset(c("a", "b", "c"), list(1, 2, 3))
st$get("a")

## The `mget` function fetches zero or more elements.
st$mget(c("a", "b", "c"))

## `mget` *always* returns a list with the same number of elements as
## the number of keys
st$mget("a")
st$mget(character(0))

## With both `mset` and `mget`, both key and namespace can be vectors;
## if either non-scalar, they must have the same length so the logic
## is fairly predictable
st$mset("x", list("a", "b"), namespace = c("ns1", "ns2"))
st$mget("x", c("ns1", "ns2"))

st$mget(c("a", "b", "x"), c("objects", "objects", "ns1"))

## ## Import / export

## Objects can be imported in and exported out of a `storr`;

## Import from a list, environment or another `storr`
st$import(list(a = 1, b = 2))
st$list()
st$get("a")

## Export to an environment (or another `storr`)
e <- st$export(new.env(parent = emptyenv()))
ls(e)
e$a

st_copy <- st$export(storr_environment())
st_copy$list()
st$get("a")

st2 <- storr::storr(driver = storr::driver_rds(tempfile("storr_")))
st2$list()
st2$import(st)
st2$list()

## ## Supported backends

## * environments (`driver_environment`) - mostly for debugging and
##   transient storage, but by far the fastest.
## * on disk with rds (`driver_rds`) - zero dependencies, quite fast,
##   will suffer under high concurrency because there is no file
##   locking.
## * DBI (`driver_dbi`) - uses (abuses?) a relational database to
##   store the data.  This is not the fastest interface but allows for
##   interprocess key/value stores where a relational database is
##   supported.  All databases supported by DBI are supported (so at
##   least SQLite, MySQL and Postgres).
## * Redis (`driver_redis`) - uses
##   [`redux`](https://github.com/richfitz/redux) to store the data in a
##   Redis (`http://redis.io`) database.  About the same speed as rds
##   (faster write, slower read at present), but can allow multiple R
##   processes to share the same set of objects.
## * rlite (`driver_rlite`) - stores data in an
##   [rlite](https://github.com/seppo0010/rlite) database using
##   [`rrlite`](https://github.com/ropensci/rrlite).  This is quite
##   quick, but is stalled for general release because `rrlite` does not
##   support windows.
## * The in-development package
##   [thor](https://github.com/richfitz/thor) provides an alternative
##   on-disk storr that can handle multiple processes on a single
##   machine.

## ## Implementation details

## `storr` includes a few useful features that are common to all
## drivers.

## ### Content addressable lookup

## The only thing that is stored against a key is the hash of some
## object.  Each driver does this a different way, but for the rds
## driver it stores small text files that list the hash in them.  So:
dir(file.path(path, "keys", "objects"))
readLines(file.path(path, "keys", "objects", "a"))
st$get_hash("a")

## Then there is one big pool of hash / value pairs:
st$list_hashes()

## in the rds driver these are stored like so:
dir(file.path(path, "data"))

## ### Environment-based caching

## Every time data passes across a `get` or `set` method, `storr`
## stores the data in an environment within the `storr` object.
## Because we store the content against its hash, it's always in sync
## with what is saved to disk.  That means that the look up process
## goes like this:
##
## 1. Ask for a key, get returned the hash of the content
## 2. Check in the caching environment for that hash and return that
## if present
## 3. If not present, read content from disk/db/wherever the driver
## stores it and save it into the caching environment
##
## Because looking up data in the environment is likely to be orders
## of magnitide faster than reading from disks or databases, this
## means that commonly accessed data will be accessed at a similar
## speed to native R objects, while still immediately reflecting
## changes to the content (because that would mean the hash changes)

## To demonstrate:
st <- storr::storr(driver = storr::driver_rds(tempfile("storr_")))

## This is the caching environent; currently empty
ls(st$envir)

## Set some key to some data:
set.seed(2)
st$set("mykey", runif(100))

## The environment now includes an object with a *name* that is the
## same as the *hash* of its contents:
ls(st$envir)

## Extract the object from the environment and hash it
st$hash_object(st$envir[[ls(st$envir)]])

## When we look up the value stored against key `mykey`, the first
## step is to check the key/hash map; this returns the key above (this
## step *does* involve reading from disk)
st$get_hash("mykey")

## It then calls `$get_value` to extract the value associated with
## that hash - the first thing that function does is try to locate the
## hash in the environment, otherwise it reads the data from wherever
## the driver stores it.
st$get_value

## The speed up is going to be fairly context dependent, but 5-10x
## seems pretty good in this case (some of the overhead is simply a
## longer code path as we call out to the driver).  For big bits of
## data and slow network connections the difference will be much more
## pronounced.
hash <- st$get_hash("mykey")
if (requireNamespace("rbenchmark")) {
  rbenchmark::benchmark(st$get_value(hash, use_cache = TRUE),
                        st$get_value(hash, use_cache = FALSE),
                        replications = 1000, order = NULL)[1:4]
}

## ### Classed exceptions

## storr uses R's exception handling system and errors inspired from
## Python to make it easy to program with `tryCatch`.

## If a key is not in the database, storr will return a `KeyError`
## (not `NULL` because storing a `NULL` value is a perfectly
## reasonable thing to do).

## If you _did_ want to return `NULL` when a key is requested but not
## present, use tryCatch in this way:
tryCatch(st$get("no_such_key"),
         KeyError = function(e) NULL)

## See `?tryCatch` for details.  The idea is that key lookup errors
## will have the class `KeyError` so will be caught here and run the
## given function (the argument `e` is the actual error object).
## Other errors will not be caught and will still throw.

## `HashErrors` will be rarer, but could happen (they might occur if
## your driver supports expiry of objects).  We can simulate that by
## setting a hash and deleting it:
##
st$set("foo", letters)
ok <- st$driver$del_object(st$get_hash("foo"))
st$flush_cache()
tryCatch(st$get("foo"),
         KeyError = function(e) NULL,
         HashError = function(e) message("Data is deleted"))

## Here the `HashError` is triggered.

## `KeyError` objects include `key` and `namespace` elements,
## `HashError` objects include a `hash` element.  They both inherit
## from `c("error", "condition")`.

## Finally, when using an external storr (see ?driver_external) storr
## will throw a `KeyErrorExternal` if the `fetch_hook` function errors
## while trying to retrieve an external resource.
