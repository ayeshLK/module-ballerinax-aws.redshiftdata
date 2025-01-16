/*
 * Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
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
import io.ballerina.runtime.api.values.BArray;
import io.ballerina.runtime.api.values.BError;
import io.ballerina.runtime.api.values.BMap;
import io.ballerina.runtime.api.values.BObject;
import io.ballerina.runtime.api.values.BStream;
import io.ballerina.runtime.api.values.BString;
import io.ballerina.runtime.api.values.BTypedesc;
import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentials;
import software.amazon.awssdk.auth.credentials.AwsCredentialsProvider;
import software.amazon.awssdk.auth.credentials.AwsSessionCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.services.redshiftdata.RedshiftDataClient;
import software.amazon.awssdk.services.redshiftdata.model.BatchExecuteStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.BatchExecuteStatementResponse;
import software.amazon.awssdk.services.redshiftdata.model.DescribeStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.DescribeStatementResponse;
import software.amazon.awssdk.services.redshiftdata.model.ExecuteStatementRequest;
import software.amazon.awssdk.services.redshiftdata.model.ExecuteStatementResponse;
import software.amazon.awssdk.services.redshiftdata.model.GetStatementResultRequest;
import software.amazon.awssdk.services.redshiftdata.model.GetStatementResultResponse;

import java.util.Objects;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Representation of {@link RedshiftDataClient} with
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
            bClient.addNativeData(Constants.NATIVE_DB_ACCESS_CONFIG, connectionConfig.dbAccessConfig());
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
                                          BMap<BString, Object> bExecuteStatementConfig) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        Object dbAccessConfig = bClient.getNativeData(Constants.NATIVE_DB_ACCESS_CONFIG);
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                ExecuteStatementRequest executeStatementRequest = CommonUtils.getNativeExecuteStatementRequest(
                        bSqlStatement, bExecuteStatementConfig, dbAccessConfig);
                ExecuteStatementResponse executeStatementResponse = nativeClient
                        .executeStatement(executeStatementRequest);
                BMap<BString, Object> bResponse = CommonUtils.getExecuteStatementResponse(executeStatementResponse);
                future.complete(bResponse);
            } catch (BError e) {
                future.complete(e);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the executeStatement: %s",
                        Objects.requireNonNullElse(e.getMessage(), "Unknown error"));
                BError bError = CommonUtils.createError(errorMsg, e);
                future.complete(bError);
            }
        });
        return null;
    }

    @SuppressWarnings("unchecked")
    public static Object batchExecuteStatement(Environment env, BObject bClient, BArray bSqlStatements,
                                               BMap<BString, Object> bExecuteStatementConfig) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        Object dbAccessConfig = bClient.getNativeData(Constants.NATIVE_DB_ACCESS_CONFIG);
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                BatchExecuteStatementRequest batchExecuteStatementRequest = CommonUtils
                        .getNativeBatchExecuteStatementRequest(bSqlStatements, bExecuteStatementConfig, dbAccessConfig);
                BatchExecuteStatementResponse batchExecuteStatementResponse = nativeClient
                        .batchExecuteStatement(batchExecuteStatementRequest);
                BMap<BString, Object> bResponse = CommonUtils
                        .getBatchExecuteStatementResponse(batchExecuteStatementResponse);
                future.complete(bResponse);
            } catch (BError e) {
                future.complete(e);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the batchExecuteStatement: %s",
                        Objects.requireNonNullElse(e.getMessage(), "Unknown error"));
                BError bError = CommonUtils.createError(errorMsg, e);
                future.complete(bError);
            }
        });
        return null;
    }

    @SuppressWarnings("unchecked")
    public static Object describeStatement(Environment env, BObject bClient, BString bStatementId) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        String statementId = bStatementId.getValue();
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                DescribeStatementResponse describeStatementResponse = nativeClient.describeStatement(
                        DescribeStatementRequest.builder().id(statementId).build());
                BMap<BString, Object> bResponse = CommonUtils.getDescribeStatementResponse(describeStatementResponse);
                future.complete(bResponse);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the describeStatement: %s",
                        Objects.requireNonNullElse(e.getMessage(), "Unknown error"));
                BError bError = CommonUtils.createError(errorMsg, e);
                future.complete(bError);
            }
        });
        return null;
    }

    public static Object getStatementResult(Environment env, BObject bClient, BString bStatementId,
                                            BTypedesc recordType) {
        RedshiftDataClient nativeClient = (RedshiftDataClient) bClient.getNativeData(Constants.NATIVE_CLIENT);
        String statementId = bStatementId.getValue();
        Future future = env.markAsync();
        EXECUTOR_SERVICE.execute(() -> {
            try {
                GetStatementResultResponse nativeResultResponse = nativeClient
                        .getStatementResult(GetStatementResultRequest.builder().id(statementId).build());
                BStream resultStream = QueryResultProcessor
                        .getRecordStream(nativeClient, statementId, nativeResultResponse, recordType);
                future.complete(resultStream);
            } catch (Exception e) {
                String errorMsg = String.format("Error occurred while executing the getQueryResult: %s",
                        Objects.requireNonNullElse(e.getMessage(), "Unknown error"));
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
                    Objects.requireNonNullElse(e.getMessage(), "Unknown error"));
            return CommonUtils.createError(errorMsg, e);
        }
        return null;
    }
}
