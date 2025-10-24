FROM debian:bookworm

COPY scripts/install_dependencies.sh /install_dependencies.sh
RUN chmod +x /install_dependencies.sh && \
      /install_dependencies.sh && \
      rm -rf /install_dependencies.sh

CMD [ "/bin/bash" ]