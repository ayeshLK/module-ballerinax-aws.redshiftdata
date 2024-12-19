/*
 * Copyright (c) 2024, WSO2 LLC. (http://www.wso2.org).
 *
 * WSO2 LLC. licenses this file to you under the Apache License,
 * Version 2.0 (the "License"); you may not use this file except
 * in compliance with the License.
 * You may obtain a copy of the License at
 *
 *    http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied. See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

package io.ballerina.lib.aws.redshiftdata;

import io.ballerina.runtime.api.Environment;
import io.ballerina.runtime.api.Future;
import io.ballerina.runtime.api.utils.StringUtils;
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BString;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.AwsSessionCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.services.redshiftdata.RedshiftDataClient;
import software.amazon.awssdk.services.redshiftdata.model.BatchExecuteStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.DescribeStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.DescribeStatementResponse;
import software.amazon.awssdk.services.redshiftdata.model.ExecuteStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.SubStatementData;

import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Representation of {@link software.amazon.awssdk.services.redshiftdata.RedshiftDataClient} with
 * utility methods to invoke as inter-op functions.
 */
public class NativeClientAdaptor {
    private static final ExecutorService EXECUTOR_SERVICE = Executors
            .newCachedThreadPool(new RedshiftDataThreadFactory());

    private NativeClientAdaptor() {
    }

    public static Object init(BObject bClient, BMap<BString, Object> bConnectionConfig) {
        try {
            ConnectionConfig connectionConfig = new ConnectionConfig(bConnectionConfig);
            AwsCredentials credentials = getCredentials(connectionConfig.authConfig());
            AwsCredentialsProvider credentialsProvider = StaticCredentialsProvider.create(credentials);
            RedshiftDataClient nativeClient = RedshiftDataClient.builder()
                    .region(connectionConfig.region())
                    .credentialsProvider(credentialsProvider)
                    .build();
            bClient.addNativeData(Constants.NATIVE_CLIENT, nativeClient);
            bClient.addNativeData(Constants.NATIVE_DATABASE_CONFIG, connectionConfig.databaseConfig());
        } catch (Exception e) {
            String errorMsg = String.format("Error occurred while initializing the Redshift client: %s",
                    e.getMessage());
            return CommonUtils.createError(errorMsg, e);
        }
        return null;
    }

    private static AwsCredentials getCredentials(AuthConfig authConfig) {
        if (Objects.nonNull(authConfig.sessionToken())) {
            return AwsSessionCredentials.create(authConfig.accessKeyId(), authConfig.secretAccessKey(),
                    authConfig.sessionToken());
        } else {
            return AwsBasicCredentials.create(authConfig.accessKeyId(), authConfig.secretAccessKey());
        }
    }

    @SuppressWarnings("unchecked")
    public static Object executeStatement(Environment env, BObject bClient, BObject bSqlStatement,
                                          Object bDatabaseConfig) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        DatabaseConfig databaseConfig;
        if (bDatabaseConfig == null)
            databaseConfig = (DatabaseConfig) bClient.getNativeData(Constants.NATIVE_DATABASE_CONFIG);
        else {
            databaseConfig = new DatabaseConfig((BMap<BString, Object>) bDatabaseConfig);
        }
        ParameterizedQuery parameterizedQuery = new ParameterizedQuery(bSqlStatement);
        ExecuteStatementRequest.Builder requestBuilder = ExecuteStatementRequest.builder()
                .clusterIdentifier(databaseConfig.clusterId())
                .database(databaseConfig.databaseName())
                .dbUser(databaseConfig.databaseUser())
                .sql(parameterizedQuery.getQueryString());
        // Set sql query parameters if available
        if (parameterizedQuery.hasParameters()) {
            requestBuilder.parameters(parameterizedQuery.getParameters());
        }

        ExecuteStatementRequest statementRequest = requestBuilder.build();
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                String statementId = nativeClient.executeStatement(statementRequest).id();
                BString bStatementId = StringUtils.fromString(statementId);
                future.complete(bStatementId);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the statement: %s",
                        e.getMessage());
                BError bError = CommonUtils.createError(errorMsg, e);
                future.complete(bError);
            }
        });
        return null;
    }

    @SuppressWarnings("unchecked")
    public static Object batchExecuteStatement(Environment env, BObject bClient, BArray bSqlStatementsArray,
                                               Object bDatabaseConfig) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        DatabaseConfig databaseConfig;
        if (bDatabaseConfig == null)
            databaseConfig = (DatabaseConfig) bClient.getNativeData(Constants.NATIVE_DATABASE_CONFIG);
        else {
            databaseConfig = new DatabaseConfig((BMap<BString, Object>) bDatabaseConfig);
        }
        String[] preparedQuery = new String[bSqlStatementsArray.size()];
        for (int i = 0; i < bSqlStatementsArray.size(); i++) {
            preparedQuery[i] = (new ParameterizedQuery((BObject) bSqlStatementsArray.get(i))).getPreparedQuery();
        }
        BatchExecuteStatementRequest batchExecuteStatementRequest = BatchExecuteStatementRequest.builder()
                .clusterIdentifier(databaseConfig.clusterId())
                .database(databaseConfig.databaseName())
                .dbUser(databaseConfig.databaseUser())
                .sqls(preparedQuery)
                .build();
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                String statementId = nativeClient.batchExecuteStatement(batchExecuteStatementRequest).id();
                DescribeStatementResponse describeStatementResponse = getDescribeStatement(nativeClient, statementId,
                        Constants.DEFAULT_TIMEOUT, Constants.DEFAULT_POLLING_INTERVAL);
                String[] subStatementIds = describeStatementResponse.subStatements().stream()
                        .map(SubStatementData::id)
                        .toArray(String[]::new);
                BArray bStatementIds = StringUtils.fromStringArray(subStatementIds);
                future.complete(bStatementIds);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the batch statement: %s",
                        e.getMessage());
                BError bError = CommonUtils.createError(errorMsg, e);
                future.complete(bError);
            }
        });
        return null;
    }

    public static Object close(BObject bClient) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        try {
            nativeClient.close();
        } catch (Exception e) {
            String errorMsg = String.format("Error occurred while closing the Redshift client: %s",
                    e.getMessage());
            return CommonUtils.createError(errorMsg, e);
        }
        return null;
    }

    // helper methods
    private static DescribeStatementResponse getDescribeStatement(RedshiftDataClient nativeClient,
                                                                  String statementId, long timeout, long pollInterval) {
        long timeoutMillis = timeout * 1000; // convert seconds to milliseconds
        long pollIntervalMillis = pollInterval * 1000; // convert seconds to milliseconds
        long startTime = System.currentTimeMillis();
        DescribeStatementRequest describeStatementRequest = DescribeStatementRequest.builder()
                .id(statementId)
                .build();
        DescribeStatementResponse response;
        while ((System.currentTimeMillis() - startTime) < timeoutMillis) {
            response = nativeClient.describeStatement(describeStatementRequest);
            switch (response.status()) {
                case FINISHED:
                    return response;
                case FAILED:
                    throw new RuntimeException("Statement execution failed");
                case ABORTED:
                    throw new RuntimeException("Statement execution aborted");
                default:
                    try {
                        Thread.sleep(pollIntervalMillis);
                    } catch (InterruptedException e) {
                        Thread.currentThread().interrupt();
                    }
            }
        }
        throw new RuntimeException("Statement execution timed out");
    }
}
