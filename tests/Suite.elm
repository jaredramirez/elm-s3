module Suite exposing (suite)

import Expect exposing (Expectation)
import S3.Internals as Internals
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Session"
        [ describe "Key building"
            [ test "no prefix" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "", fileName = "bar" })
                        "bar"
            , test "plain prefix" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "foo", fileName = "bar" })
                        "foo/bar"
            , test "prefix with a leading slash" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "/foo", fileName = "bar" })
                        "foo/bar"
            , test "prefix with leading & trailing slashes" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "/foo/", fileName = "bar" })
                        "foo/bar"
            , test "fileName with leading slashes" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "foo", fileName = "/bar" })
                        "foo/bar"
            , test "prefix with trailing slash and fileName with leading slashes" <|
                \_ ->
                    Expect.equal
                        (Internals.buildUploadKey { prefix = "foo/", fileName = "/bar" })
                        "foo/bar"
            ]
        ]
