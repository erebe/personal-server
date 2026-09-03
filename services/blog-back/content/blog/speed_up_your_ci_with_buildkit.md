+++
title = "Buildkit: Speed up your (Rust) CI build by using image cache stage"
description = "Learn how to write a versatile Dockerfile useful in CI and local machine by using Buildkit and image cache stage"
date = 2021-06-09
[extra]
header = '''<iframe class="hcenter" src="https://open.spotify.com/embed/track/5Twubz3SaJmTykgAn8t7IS" width="300" height="380" frameborder="0" allowtransparency="true" allow="encrypted-media"></iframe>'''
tags = ["rust", "docker", "image", "cache", "CI", "continuous integration", "buildkit"]
+++

<p style="border-style: double; padding: 5px 0px 5px 5px">
tl;dr:
<br/>
  - Learn to write a single dockerfile suitable for CI and local dev environment
<br/>
  - Create a caching stage, use `--target` to create cache image and use buildkit `--build-arg` to dynamically update your image source 
</p>


[Reddit discussion](https://www.reddit.com/r/rust/comments/nvpkx4/buildkit_speed_up_your_rust_ci_build_by_using/)

--- 
<br/>

Even if you are a possessor of an AMD Ryzen processor, compiling Rust's projects can take quite sometimes..., especially if you are starting from a fresh clone and doing it from scratch.
<br/>
I often see this situation in CI, we create a Dockerfile that contains 2 stages/targets. One for building artifacts and the other one that is supposed to be our running image

```dockerfile
# Builder Stage
FROM rust:1.52.1 AS builder

WORKDIR /app
COPY app/Cargo.lock .
COPY app/Cargo.toml .
RUN mkdir .cargo
RUN cargo vendor > .cargo/config

COPY . .
RUN cargo build --release


# Runner Stage
FROM debian:stable-slim

RUN useradd -ms /bin/bash app && \
  apt-get update && \
  apt install -y --no-install-recommends ca-certificates && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists

WORKDIR /home/app
COPY --from=builder backend/target/release/my-little-app my-little-app

CMD chown -R app:app . && \
    runuser -u app ./my-little-app
```

This kind of Dockerfile is great for developing and building your project on your local machine, but not too much if you want to build it in a CI.

The good part is that
```dockerfile
COPY app/Cargo.lock .
COPY app/Cargo.toml .
RUN mkdir .cargo
RUN cargo vendor > .cargo/config
```
We are extracting the fetch of our dependencies in some immutable layer (as long as Cargo.lock and Cargo.toml) does not change.
So we are leveraging the docker build cache in order to cache our dependencies.
The first time this image is build, we are going to pay the cost of updating the index of crates.io and fetching our dependencies,
but subsequent build are going to re-use the docker layer already computed as nothing changed.
</br>
[To learn more about docker layer](https://dzone.com/articles/docker-layers-explained)

Great, so problem solved, no ? We already have our cache image ?

Well, this Dockerfile is great if you build it on your local machine as you are going to re-use your already cached docker layers.
But once put in a CI, it will fall short as this docker layer cache is local to a single machine and not distributed across your whole CI fleet.

So once run in a CI, there is a lot of chance that you are building the image from scratch again and again (especially with docker in docker) without the possibility to benefit from a cache.

<br/>
<br/>
 
# Cache stage

Want we want to do is have a cache for our builder, but remotely accessible from any jobs in your CI.
And guess what ? You already have this feature with images !

It would be great if instead of 
```dockerfile
FROM rust:1.52 AS builder
```
we could have 
```dockerfile
FROM my_app_builder_image_cache AS builder
```

Luckily, it is already possible ! We can add in on our Dockerfile a new stage in order to create our cache image
```dockerfile
#######################################
# Cache image
########################################
FROM rust:1.52 AS builder_cache

# Add rust component is will be installed once
RUN rustup component add rustfmt clippy

COPY . ./

# Build our compilation cache
RUN cargo build --tests
RUN cargo build --release
# Cleanup non related artifacts
RUN find . ! -path './target*' -exec rm -rf {} \;  || exit 0


########################################
# Builder Stage, we re-euse our cache
########################################
FROM builder_cache AS builder

WORKDIR /app
COPY . .

# As we have cargo fmt now, we can use it
RUN cargo fmt --all -- --check --color=always || (echo "Use cargo fmt to format your code"; exit 1)
RUN cargo rustc -- -D warnings || (echo "Warnings are not allowed"; exit 1)
RUN cargo build --tests || (echo "Fix the tests !!!!"; exit 1)
RUN cargo build --release


########################################
# Runner Stage
# Nothing change in this stage
########################################
FROM debian:stable-slim

RUN useradd -ms /bin/bash app && \
  apt-get update && \
  apt install -y --no-install-recommends ca-certificates && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists

WORKDIR /home/app
COPY --from=builder backend/target/release/my-little-app my-little-app

CMD chown -R app:app . && \
    runuser -u app ./my-little-app
```

Now we have a cache image, all we need to do to build it, is specifying the target during our docker build
```
docker build -t myapp:cache --target=builder_cache .
```
and if we don't specify any target it is going to rebuild everything as expected
```
docker build -t myapp:final .
```

That's great, but now our Dockerfile is going to rebuild everything from scratch every time, as in the cache image we put a `COPY . ./`.
<br/>
Every time the source code change, docker will detect it and rebuild this layer and thus the whole cache stage.

What we want is to tell docker to use our cached image as the builder stage, without worrying about if the cache is in sync or not.
<br/>
We want a kind of if else regarding which image to depend on
```
if use_cache_image == true
FROM myapp:cache AS builder
else 
FROM builder_cache AS builder
```

<br/>
<br/>

# Enter Buildkit


[Buildkit](https://docs.docker.com/develop/develop-images/build_enhancements/) is the new docker engine for building images, which aims
to be `concurrent, cache-efficient, and Dockerfile-agnostic builder toolkit.
<br/>
See their [GitHub repository](https://github.com/moby/buildkit) for more information.

<br/>
By default, when you are using docker build it is not activated. To enable it you need to set an env variable

```bash
export  DOCKER_BUILDKIT=1
# or, when you run docker
DOCKER_BUILDKIT=1 docker build .
```

Give it a try, and you will notice, that the output of docker build changed !

Thanks to Buildkit, we have now new command line flags to pass to our `docker build`, and one of particular interest is `build-arg`
```bash
DOCKER_BUILDKIT=1 docker build --help
#...
      --build-arg list          Set build-time variables
#...

```

With `build-arg` we can inject variable in our Dockerfile with some minor changes
```dockerfile
# ARG needs to be defined at top level of the dockerfile
# before any FROM.
ARG BUILDER_IMAGE=builder_cache

#######################################
# Cache image
# This stage does not change
########################################
FROM rust:1.52 AS builder_cache

# ...


########################################
# Builder Stage
# now use the source image defined by 
# ARG BUILDER_IMAGE
########################################
FROM ${BUILDER_IMAGE} AS builder

# ...

########################################
# Runner Stage
# Nothing change in this stage
########################################
FROM debian:stable-slim

# ...

```

The thing to notice here, is that now the base image from our builder is now controlled by the `ARG BUILDER_IMAGE`
<br/>
If we don't specify any argument during our `docker build` the image is going to build by executing the stage `builder_cache` and work as expected.

But now, if we specify a build `--build-arg` and a `--target` it is possible to skip this stage if we don't want/need it.
<br>
So when we need to build and push our cache image, all we need to is
```bash
# Build and push our cache
DOCKER_BUILDKIT=1 docker build -t myapp:cache --target=builder_cache .
docker push myapp:cache
```

when we went to build our application by reusing our cache, all what is left to do is a
```bash
DOCKER_BUILDKIT=1 docker build -t myapp:$COMMIT_SHA1 --target=final --build-arg BUILDER_IMAGE=myapp:cache .
```

and if we want to build from scratch
```bash
DOCKER_BUILDKIT=1 docker build -t myapp:$COMMIT_SHA1 .
```


With the help of Buildkit, in a single Dockerfile we have now a build recipe that is useful locally, but also in any CI as there is a way to build, push and retrieve a cache for this job.

As the saying goes, There are two hard things in computer science: cache invalidation, naming things, and off-by-one errors.
<br/>
Our cache is going to become stale/invalid over time as the code and its dependencies go out of sync.

But, we just need to create a job to rebuild our cache and re-push it. Which boil down to re-doing  the previous command
```bash
# Build and push our cache
DOCKER_BUILDKIT=1 docker build -t myapp:cache --target=builder_cache .
docker push myapp:cache
```


<br/>
<br/>

# Conclusion

  - Traditional builder & runner multistage Dockerfile are great for local build
  - But often fall short when put in a CI as we can't leverage docker build layer cache
  - Thanks to Buildkit and `--build-arg` it is possible to create a new stage to create a cache image
  - That can be re-used or not in the builder & runner stage
  - Thus reaching in a single Dockerfile, a build recipe suitable to for CI and local usage


<br/>
<br/>

### Complete example

```dockerfile
ARG BUILDER_IMAGE=builder_cache

#######################################
# Cache image
########################################
FROM rust:1.52 AS builder_cache

# Add rust component is will be installed once
RUN rustup component add rustfmt clippy

COPY . ./

# Build our compilation cache
RUN cargo build --tests
RUN cargo build --release
# Cleanup non related artifacts
RUN find . ! -path './target*' -exec rm -rf {} \;  || exit 0


########################################
# Builder Stage
########################################
FROM ${BUILDER_IMAGE} AS builder

WORKDIR /app
COPY . .

# As we have cargo fmt now, we can use it
RUN cargo fmt --all -- --check --color=always || (echo "Use cargo fmt to format your code"; exit 1)
RUN cargo rustc -- -D warnings || (echo "Warnings are not allowed"; exit 1)
RUN cargo build --tests || (echo "Fix the tests !!!!"; exit 1)
RUN cargo build --release


########################################
# Runner Stage
########################################
FROM debian:stable-slim

RUN useradd -ms /bin/bash app && \
  apt-get update && \
  apt install -y --no-install-recommends ca-certificates && \
  apt-get clean && \
  rm -rf /var/lib/apt/lists

WORKDIR /home/app
COPY --from=builder backend/target/release/my-little-app my-little-app

CMD chown -R app:app . && \
    runuser -u app ./my-little-app
```


```bash 
# Build and push our cache
DOCKER_BUILDKIT=1 docker build -t myapp:cache --target=builder_cache .
docker push myapp:cache

# Build app with cache
DOCKER_BUILDKIT=1 docker build -t myapp:$COMMIT_SHA1 --target=final --build-arg BUILDER_IMAGE=myapp:cache .

# Build app from sratch
DOCKER_BUILDKIT=1 docker build -t myapp:$COMMIT_SHA1 .
```
