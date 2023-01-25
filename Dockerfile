# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements. See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership. The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License. You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied. See the License for the
# specific language governing permissions and limitations
# under the License.
#  
FROM azul/zulu-openjdk:17 AS builder

RUN apt-get update -qq && apt-get install -y wget

COPY . fineract
WORKDIR fineract


RUN ./gradlew --no-daemon -q  -x compileTestJava -x test -x spotlessJavaCheck -x spotlessJava bootJar
RUN mv /fineract/fineract-provider/build/libs/*.jar /fineract/fineract-provider/build/libs/fineract-provider.jar

#building pentaho reports
WORKDIR /fineract/fineract-pentaho
RUN chmod +x gradlew
RUN ./gradlew --no-daemon -q -x test build

# https://issues.apache.org/jira/browse/LEGAL-462
# https://issues.apache.org/jira/browse/FINERACT-762
# We include an alternative JDBC driver (which is faster, but not allowed to be default in Apache distribution)
# allowing implementations to switch the driver used by changing start-up parameters (for both tenants and each tenant DB)
# The commented out lines in the docker-compose.yml illustrate how to do this.
WORKDIR /app/libs
RUN wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/8.0.23/mysql-connector-java-8.0.23.jar
RUN cp /fineract/fineract-pentaho/build/dist/lib/*.jar /app/libs/
# =========================================

FROM azul/zulu-openjdk:17 as fineract

#pentaho copy
COPY --from=builder /fineract/fineract-pentaho/pentahoReports/*.properties /root/.mifosx/pentahoReports/
COPY --from=builder /fineract/fineract-pentaho/pentahoReports/*.prpt /root/.mifosx/pentahoReports/

COPY --from=builder /fineract/fineract-provider/build/libs/ /app
COPY --from=builder /app/libs /app/libs

ENV TZ="UTC"
ENV FINERACT_HIKARI_DRIVER_SOURCE_CLASS_NAME="com.mysql.cj.jdbc.Driver"
ENV FINERACT_HIKARI_MINIMUM_IDLE="1"
ENV FINERACT_HIKARI_MAXIMUM_POOL_SIZE="20"
ENV FINERACT_HIKARI_IDLE_TIMEOUT="120000"
ENV FINERACT_HIKARI_CONNECTION_TIMEOUT="300000"

ENTRYPOINT ["java", "-Dloader.path=/app/libs/", "-jar", "/app/fineract-provider.jar"]
