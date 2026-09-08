FROM ghcr.io/getzola/zola:v0.23.4

COPY . .
RUN ["zola", "build"]

ENTRYPOINT [ "/busybox-x86_64" ]
