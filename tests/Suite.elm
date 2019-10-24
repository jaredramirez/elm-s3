module Suite exposing (suite)

import Expect exposing (Expectation)
import S3
import Test exposing (Test, describe, test)


suite : Test
suite =
    describe "Session"
        [ test "Key building: no prefix" <|
            \_ -> Expect.equal (S3.buildUploadKey "" "bar") "bar"
        , test "Key building: plain prefix" <|
            \_ -> Expect.equal (S3.buildUploadKey "foo" "bar") "foo/bar"
        , test "Key building: prefix with a leading slash" <|
            \_ -> Expect.equal (S3.buildUploadKey "/foo" "bar") "foo/bar"
        , test "Key building: prefix with leading & trailing slashes" <|
            \_ -> Expect.equal (S3.buildUploadKey "/foo/" "bar") "foo/bar"
        ]
