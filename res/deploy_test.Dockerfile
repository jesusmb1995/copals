ARG BASE
FROM ${BASE}

ARG BASE_TOOLS
ARG BASHUNIT_BIN
ARG CONTEXT_DIR=pkg
ARG USERNAME=user

WORKDIR /tests
COPY ${CONTEXT_DIR}/${BASHUNIT_BIN} /usr/local/bin/bashunit
COPY ${CONTEXT_DIR}/tests.sh /tests/tests.sh
COPY ${CONTEXT_DIR}/screenshot_tests.sh /tests/screenshot_tests.sh
COPY ${CONTEXT_DIR}/run_tests.sh /tests/run_tests.sh
COPY ${CONTEXT_DIR}/meta.json /tests/meta.json

COPY --from=${BASE_TOOLS} / /

USER root
RUN chmod +x /usr/local/bin/bashunit \
 && (useradd --create-home --shell /bin/bash ${USERNAME} || true)

USER ${USERNAME}

CMD ["/bin/bash", "/tests/run_tests.sh"]
