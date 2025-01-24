//  Copyright (c) 2025, WSO2 LLC. (http://www.wso2.org).
//
//  WSO2 LLC. licenses this file to you under the Apache License,
//  Version 2.0 (the "License"); you may not use this file except
//  in compliance with the License.
//  You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing,
//  software distributed under the License is distributed on an
//  "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
//  KIND, either express or implied. See the License for the
//  specific language governing permissions and limitations
//  under the License.

import ballerina/sql;
import ballerina/test;

type User record {|
    int user_id;
    string username;
    string email;
    int age;
|};

type UserWithoutEmailField record {|
    int user_id;
    string username;
    int age;
|};

type UserOpenRecord record {
};

type SupportedTypes record {|
    int int_type;
    int bigint_type;
    float double_type;
    boolean boolean_type;
    string string_type;
    () nil_type;
|};

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testBasicQueryResult() returns error? {
    User[] expectedUsers = [
        {user_id: 1, username: "JohnDoe", email: "john.doe@example.com", age: 25},
        {user_id: 2, username: "JaneSmith", email: "jane.smith@example.com", age: 30},
        {user_id: 3, username: "BobJohnson", email: "bob.johnson@example.com", age: 22}
    ];

    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<User, Error?> resultStream = check redshiftdata->getStatementResult(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 3);
    test:assertEquals(resultArray[0], expectedUsers[0]);
    test:assertEquals(resultArray[1], expectedUsers[1]);
    test:assertEquals(resultArray[2], expectedUsers[2]);
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testParameterizedQueryResult() returns error? {
    int user_id = 1;
    sql:ParameterizedQuery query = `SELECT * FROM Users WHERE user_id = ${user_id};`;

    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<User, Error?> resultStream = check redshiftdata->getStatementResult(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 1);
    test:assertEquals(resultArray[0].username, "JohnDoe");
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testSupportedTypes() returns error? {
    SupportedTypes data = {
        int_type: 12,
        bigint_type: 9223372036854774807,
        double_type: 123.34,
        boolean_type: true,
        string_type: "test",
        nil_type: ()
    };

    Client redshiftdata = check new Client(testConnectionConfig);

    sql:ParameterizedQuery insertQuery = `INSERT INTO SupportedTypes (
        int_type, bigint_type, double_type, boolean_type, string_type, nil_type) VALUES 
        (${data.int_type}, ${data.bigint_type}, ${data.double_type}, ${data.boolean_type},
         ${data.string_type},  ${data.nil_type}
        );`;
    _ = check redshiftdata->executeStatement(insertQuery);

    sql:ParameterizedQuery selectQuery = `SELECT * FROM SupportedTypes;`;
    ExecutionResponse res = check redshiftdata->executeStatement(selectQuery);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<SupportedTypes, Error?> queryResult = check redshiftdata->getStatementResult(res.statementId);

    SupportedTypes[] resultArray = check from SupportedTypes item in queryResult
        select item;

    test:assertEquals(resultArray.length(), 1);
    test:assertEquals(resultArray[0], data);
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testNoQueryResult() returns error? {
    sql:ParameterizedQuery query = `DROP TABLE IF EXISTS non_existent_table;`;

    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<User, Error?>|Error queryResult = redshiftdata->getStatementResult(res.statementId);
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        test:assertEquals(errorDetails.errorMessage, "Query does not have result. Please check query status with " +
                "DescribeStatement.");
    }
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testNoResultRows() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users WHERE user_id = 0;`;
    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<User, Error?> resultStream = check redshiftdata->getStatementResult(res.statementId);
    User[] resultArray = check from User user in resultStream
        select user;

    test:assertEquals(resultArray.length(), 0);
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testInvalidStatementId() returns error? {
    Client redshiftdata = check new Client(testConnectionConfig);
    StatementId invalidStatementId = "InvalidStatementId";
    stream<User, Error?>|Error queryResult = redshiftdata->getStatementResult(invalidStatementId);
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        string errorMessage = errorDetails.errorMessage ?: "";
        test:assertTrue(errorMessage.startsWith("id must satisfy regex pattern:"));
    }
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testIncorrectStatementId() returns error? {
    Client redshiftdata = check new Client(testConnectionConfig);
    stream<User, Error?>|Error queryResult = redshiftdata->getStatementResult("70662acc-f334-46f8-b953-3a9546796d7k");
    test:assertTrue(queryResult is Error);
    if queryResult is Error {
        ErrorDetails errorDetails = queryResult.detail();
        test:assertEquals(errorDetails.httpStatusCode, 400);
        test:assertEquals(errorDetails.errorMessage, "Query does not exist.");
    }
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testMissingFieldInUserType() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<UserWithoutEmailField, Error?>|Error resultStream = redshiftdata->getStatementResult(res.statementId);
    test:assertTrue(resultStream is Error);
    if resultStream is Error {
        test:assertEquals(resultStream.message(), "Error occurred while executing the getQueryResult: " +
                "Error occurred while creating the Record Stream: Field 'email' not found in the record type.");
    }
    check redshiftdata->close();
}

@test:Config {
    groups: ["getStatementResult"]
}
isolated function testUserWithOpenRecord() returns error? {
    sql:ParameterizedQuery query = `SELECT * FROM Users;`;
    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    _ = check waitForCompletion(redshiftdata, res.statementId);
    stream<UserOpenRecord, Error?> resultStream = check redshiftdata->getStatementResult(res.statementId);
    UserOpenRecord[] resultArray = check from UserOpenRecord user in resultStream
        select user;
    test:assertEquals(resultArray[0],
            {"user_id": 1, "email": "john.doe@example.com", "age": 25, "username": "JohnDoe"});
    check redshiftdata->close();
}

@test:Config {
    groups: ["queryResult"]
}
isolated function testResultPagination() returns error? {
    sql:ParameterizedQuery query = `SELECT 
        a.n + b.n * 10 + c.n * 100 + d.n * 1000 AS num,
        REPEAT('X', 100000) AS large_column -- Generates a string of 10000 'X's
        FROM 
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) a,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) b,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) c,
            (SELECT 0 AS n UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL SELECT 8 UNION ALL SELECT 9) d
        WHERE 
        a.n + b.n * 10 + c.n * 100 + d.n * 1000 <= 1600;
        `;

    Client redshiftdata = check new Client(testConnectionConfig);
    ExecutionResponse res = check redshiftdata->executeStatement(query);
    DescriptionResponse descriptionResponse =
        check waitForCompletion(redshiftdata, res.statementId);

    int resultSize = descriptionResponse.resultSize / 1024 / 1024; // Convert bytes to MB
    int totalRows = descriptionResponse.resultRows;
    test:assertTrue(resultSize >= 150);

    stream<record {int num;}, Error?> resultStream = check redshiftdata->getStatementResult(res.statementId);
    record {int num;}[] resultArray = check from var item in resultStream
        select item;

    test:assertEquals(resultArray.length(), totalRows);
    check redshiftdata->close();
}
