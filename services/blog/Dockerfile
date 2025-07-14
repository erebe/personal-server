FROM ghcr.io/getzola/zola:v0.21.0

COPY . .
RUN ["zola", "build"]

ENTRYPOINT [ "/busybox-x86_64" ]
