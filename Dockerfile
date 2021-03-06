#
# DSpace image
#

FROM tomcat:7-jre8
LABEL maintainer "Santiago Tettamanti <santi.tettamanti96@gmail.com>"

# Allow custom DSpace hostname at build time (default to localhost if undefined)
# To override, pass --build-arg DSPACE_HOSTNAME=repo.example.org to docker build
ARG DSPACE_HOSTNAME=localhost
# Cater for environments where Tomcat is being reverse proxied via another HTTP
# server like nginx on port 80, for example. DSpace needs to know its publicly
# accessible URL for various places where it writes its own URL.
ARG DSPACE_PROXY_PORT=8080

# Environment variables
ENV DSPACE_VERSION=6.2 \
    DSPACE_GIT_URL=https://github.com/CICBA/DSpace.git \
    DSPACE_HOME=/dspace \
    DSPACE_INSTALL=/tmp/dspace/install
ENV CATALINA_OPTS="-Xmx512M -Dfile.encoding=UTF-8" \
    MAVEN_OPTS="-XX:+TieredCompilation -XX:TieredStopAtLevel=1" \
    PATH=$CATALINA_HOME/bin:$DSPACE_HOME/bin:$PATH

WORKDIR /tmp

# Install runtime and dependencies
RUN apt-get update && apt-get install -y \
    ant \
    maven \
    nano \
    postgresql-client \
    git \
    imagemagick \
    ghostscript \
    openjdk-8-jdk-headless \
    less \
    cron \
    && rm -rf /var/lib/apt/lists/*

# Add a non-root user to perform the Maven build. DSpace's Mirage 2 theme does
# quite a bit of bootstrapping with npm and bower, which fails as root. Also
# change ownership of DSpace and Tomcat install directories.
RUN useradd -r -s /bin/bash -m -d "$DSPACE_HOME" dspace \
    && chown -R dspace:dspace "$DSPACE_HOME" "$CATALINA_HOME"

# Copy customized Catalina configuration
COPY config/webapps/xmlui.xml $CATALINA_HOME/conf/Catalina/localhost/xmlui.xml
COPY config/webapps/solr.xml $CATALINA_HOME/conf/Catalina/localhost/solr.xml


RUN sed -i "s#docBase=\"\$DSPACE_HOME#docBase=\"$DSPACE_INSTALL#" $CATALINA_HOME/conf/Catalina/localhost/xmlui.xml
RUN sed -i "s#docBase=\"\$DSPACE_HOME#docBase=\"$DSPACE_INSTALL#" $CATALINA_HOME/conf/Catalina/localhost/solr.xml


# Tweak default Tomcat server configuration
COPY config/server.xml "$CATALINA_HOME"/conf/server.xml

# Adjust the Tomcat connector's proxyPort
RUN sed -i "s/DSPACE_PROXY_PORT/$DSPACE_PROXY_PORT/" "$CATALINA_HOME"/conf/server.xml

# Install root filesystem
COPY rootfs /

# Docker's COPY instruction always sets ownership to the root user, so we need
# to explicitly change ownership of those files and directories that we copied
# from rootfs.
RUN chown dspace:dspace $DSPACE_HOME

# Make sure the crontab uses the correct DSpace directory
RUN sed -i "s#DSPACE=/dspace#DSPACE=$DSPACE_INSTALL#" /etc/cron.d/dspace-maintenance-tasks

WORKDIR $DSPACE_HOME

USER dspace

RUN mkdir .m2

USER root

# Build info
RUN echo "Debian GNU/Linux `cat /etc/debian_version` image. (`uname -rsv`)" >> /root/.built \
    && echo "- with `java -version 2>&1 | awk 'NR == 2'`" >> /root/.built \
    && echo "- with DSpace $DSPACE_VERSION on Tomcat $TOMCAT_VERSION"  >> /root/.built \
    && echo "\nNote: if you need to run commands interacting with DSpace you should enter the" >> /root/.built \
    && echo "container as the dspace user, ie: docker exec -it -u dspace dspace /bin/bash" >> /root/.built

EXPOSE 8080
VOLUME /tmp/dspace
# will run `start-dspace.sh` script as root
CMD ["start-dspace.sh"]
