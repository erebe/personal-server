FROM balthek/zola:0.13.0

COPY . .
RUN ["zola", "build"]

ENTRYPOINT [ "/asmttpd" ]
