ARG DEBIAN_VERSION=buster
FROM matrixdotorg/sytest:buster

RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    ca-certificates curl file \
    build-essential \
    openssl libssl-dev pkg-config \
    autoconf automake autotools-dev libtool xutils-dev && \
    rm -rf /var/lib/apt/lists/*

ADD install-deps.pl ./install-deps.pl
ADD cpanfile ./cpanfile
RUN perl ./install-deps.pl -T
RUN rm cpanfile install-deps.pl

RUN wget -q https://raw.githubusercontent.com/matrix-org/sytest/develop/keys/ca.crt -O /usr/local/share/ca-certificates/sytest_ca.crt
RUN chmod 644 /usr/local/share/ca-certificates/sytest_ca.crt && update-ca-certificates

RUN curl https://sh.rustup.rs -sSf | \
    sh -s -- --default-toolchain nightly -y

ENV PATH=/root/.cargo/bin:$PATH

# This is where we expect conduit to be binded to from the host
RUN mkdir -p /src

ENTRYPOINT [ "/bin/bash", "/bootstrap.sh", "conduit" ]
