ARG ARCH
FROM ${ARCH}debian:stable-slim

# TODO: optimize image size

ARG TARGETOS
ARG TARGETARCH

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

# Update system and install core packages/dependencies
RUN apt-get update \
&& apt-get upgrade -y \
&& apt-get install --no-install-recommends -y \
  apt-transport-https \
  autoconf \
  automake \
  ca-certificates \
  cmake \
  coreutils \
  curl \
  locales \
  doxygen \
  g++ \
  gettext \
  git \
  gnupg \
  libtool \
  libtool-bin \
  make \
  pkg-config \
  sudo \
  tar \
  unzip \
  wget \
  zip \
&& rm -rf /var/lib/apt/lists/*

# Download and build Neovim from latest source
# NOTE: allow a specific version of Neovim to be installed
RUN git clone https://github.com/neovim/neovim /tmp/neovim
WORKDIR /tmp/neovim
RUN make CMAKE_BUILD_TYPE=RelWithDebInfo && make install && rm -r /tmp/neovim

# Set correct locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

# Install (global) dependencies (tools, formatters and LSPs)
RUN apt-get update \
&& apt-get install --no-install-recommends -y \
fzf \
fd-find \
ripgrep \
python3-pip \
npm \
&& npm i -g \
prettier \
eslint \
bash-language-server \
dockerfile-language-server-nodejs \
yaml-language-server \
typescript \
typescript-language-server \
vscode-langservers-extracted \
&& rm -rf /var/lib/apt/lists/* \
&& ln -s "$(which fdfind)" /usr/bin/fd

RUN curl -sLo go.tar.gz "https://go.dev/dl/go1.18.linux-${TARGETARCH}.tar.gz" \
&& tar -C /usr/local/bin -xzf go.tar.gz \
&& rm go.tar.gz

# Add user 'nvim' and allow passwordless sudo
RUN adduser --disabled-password --gecos '' nvim \
&& adduser nvim sudo \
&& echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

USER nvim
WORKDIR /home/nvim

# Install (user only) dependencies (formatters and LSPs)
ENV PATH=$PATH:/usr/local/bin/go/bin/:/home/nvim/.local/bin:/home/nvim/.local/bin/bin:/home/nvim/go/bin:/home/nvim/.cargo/bin
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN pip3 install --no-cache-dir --user pyright black pynvim yamllint \
&& go install golang.org/x/tools/cmd/goimports@latest \
&& go install mvdan.cc/gofumpt@latest \
&& go install golang.org/x/tools/gopls@latest \
&& curl https://sh.rustup.rs -sSf | bash -s -- -y \
&& cargo install stylua \
&& curl -sLo tf-ls.zip "https://releases.hashicorp.com/terraform-ls/0.27.0/terraform-ls_0.27.0_linux_${TARGETARCH}.zip" \
&& unzip -d ~/.local/bin tf-ls.zip \
&& rm tf-ls.zip \
&& curl -sLo tf.zip "https://releases.hashicorp.com/terraform/1.2.1/terraform_1.2.1_${TARGETOS}_${TARGETARCH}.zip" \
&& unzip -d ~/.local/bin tf.zip \
# workaround for naming amd64 as x64
&& if [[ "${TARGETARCH}" == "amd64" ]]; then TARGETARCH=x64; fi \
&& echo "${TARGETARCH}" \
&& curl -sLo lua-lsp.tar.gz "https://github.com/sumneko/lua-language-server/releases/download/3.2.4/lua-language-server-3.2.4-linux-${TARGETARCH}.tar.gz" \
#FIX: extracted very much stuff besides the executable
&& tar -C ~/.local/bin/ -xzf lua-lsp.tar.gz \
&& rm lua-lsp.tar.gz \
&& rm tf.zip

# Copy Neovim config into the image
RUN mkdir -p .config/nvim
COPY --chown=nvim:nvim . .config/nvim
# Bootstrap Packer
RUN git clone --depth 1 https://github.com/wbthomason/packer.nvim \
 ~/.local/share/nvim/site/pack/packer/start/packer.nvim \
# Install plugins via Packer
&& nvim --headless -c 'autocmd User PackerComplete quitall' -c 'PackerSync' || true \
# we need to wait for parsers to be installed as this is apparently not blocking
&& nvim --headless -c 'TSInstall' +"sleep 15" +qa


ENTRYPOINT ["/bin/bash", "-c", "nvim"]
