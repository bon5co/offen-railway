FROM offen/offen:v1.4.2@sha256:4a69f8cbcdbff26505e728ad803a9b8ff6752bd10330749633bc507276e52c5d

USER root
COPY railway-entrypoint.sh /usr/local/bin/railway-entrypoint.sh
RUN chmod 755 /usr/local/bin/railway-entrypoint.sh
USER offen

# Fixed so the tracker snippet in the README is correct for every deploy of this
# template; offen setup is called with -forceid, and the id is only meaningful
# inside the deployment's own database.
ENV OFFEN_ROOT_ACCOUNT_ID=8f3a5c21-0d47-4b6e-9a52-1c8e7f40b3d9

ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/railway-entrypoint.sh"]
