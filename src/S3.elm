module S3 exposing
    ( Config, config, withPrefix, withSuccessActionStatus, withAwsS3Host, withAcl, withTimeout
    , FileData, Response, uploadFileCmd, uploadFileTask, uploadFileHttp, uploadFile
    )

{-| This package helps make uploading file to [Amazon S3](https://aws.amazon.com/s3/) quick and easy.

Take a look at the [`README`](https://package.elm-lang.org/packages/jaredramirez/elm-s3/latest/) for an example!


# Creating a Config

@docs Config, config, withPrefix, withSuccessActionStatus, withAwsS3Host, withAcl, withTimeout


# Uploading a file

@docs FileData, Response, uploadFileCmd, uploadFileTask, uploadFileHttp, uploadFile

-}

import Bytes exposing (Bytes)
import Dict
import File exposing (File)
import Http
import S3.Internals as Internals
import Task exposing (Task)
import Time exposing (Posix)



-- Config --


{-| Opaque configuration type for S3 requests
-}
type alias Config =
    Internals.Config


{-| Create S3 config with the required files common across all requets
-}
config :
    { accessKey : String
    , secretKey : String
    , bucket : String
    , region : String
    }
    -> Config
config { accessKey, secretKey, bucket, region } =
    Internals.Config
        { awsAccessKey = accessKey
        , awsSecretKey = secretKey
        , bucket = bucket
        , region = region
        , awsS3Host = awsS3Host
        , prefix = ""
        , acl = awsAcl
        , successActionStatus = successActionStatus
        , maybeTimeout = Nothing
        }


{-| Add a custom S3 host. This defaults to `s3.amazonaws.com`.

    config |> withAwsS3Host "customhost.aws.com"

-}
withAwsS3Host : String -> Config -> Config
withAwsS3Host customAwsS3Host (Internals.Config record) =
    Internals.Config { record | awsS3Host = customAwsS3Host }


{-| Add a prefix to the file being uploaded. This is helpful to
specify a sub directory to upload the file to.

    config |> withPrefix "my/sub/dir/"

-}
withPrefix : String -> Config -> Config
withPrefix prefix (Internals.Config record) =
    Internals.Config { record | prefix = withPrefixHelp prefix }


withPrefixHelp : String -> String
withPrefixHelp prefix =
    -- Are there other validations to do here?
    if String.endsWith "/" prefix then
        String.dropRight 1 prefix

    else
        prefix


{-| Add a custom acl (Access Control List) for the uploaded document.
**This defaults to `public-read`**

    config |> withAcl "private"

-}
withAcl : String -> Config -> Config
withAcl prefix (Internals.Config record) =
    Internals.Config { record | prefix = prefix }


{-| Add a custom success HTTP status. This defaults to `201`.

    config |> withSuccessActionStatus 200

-}
withSuccessActionStatus : Int -> Config -> Config
withSuccessActionStatus int (Internals.Config record) =
    Internals.Config { record | successActionStatus = int }


{-| Add a timeout to the network request. From the elm-http docs: "The timeout is the number of milliseconds you are willing to wait before giving up."

    config |> withTimeout 5000

-}
withTimeout : Float -> Config -> Config
withTimeout float (Internals.Config record) =
    Internals.Config { record | maybeTimeout = Just float }



-- Task --


{-| All the information needed for a specific file upload.
-}
type alias FileData =
    { fileName : String
    , contentType : String
    , file : File
    }


{-| The response from the upload request.
-}
type alias Response =
    { etag : String
    , location : String
    , bucket : String
    , key : String
    }


{-| Upload a file
-}
uploadFileCmd : (Result Http.Error Response -> msg) -> FileData -> Config -> Cmd msg
uploadFileCmd toMsg fileData qualConfig =
    uploadFileTask fileData qualConfig
        |> Task.attempt toMsg


{-| Deprecated. Use `uploadFileCmd` instead
-}
uploadFile : FileData -> Config -> (Result Http.Error Response -> msg) -> Cmd msg
uploadFile fileData qualConfig toMsg =
    uploadFileCmd toMsg fileData qualConfig


{-| Upload a file but as a task. This is helpful if you need to upload a file, then
get it's location from the [`Response`](#Response) and send that on your server.
-}
uploadFileTask : FileData -> Config -> Task Http.Error Response
uploadFileTask fileData ((Internals.Config record) as qualConfig) =
    Time.now
        |> Task.andThen
            (\today ->
                let
                    url =
                        Internals.makeUrl qualConfig

                    key =
                        Internals.buildUploadKey
                            { prefix = record.prefix
                            , fileName = fileData.fileName
                            }

                    parts =
                        Internals.generatePolicy key
                            fileData.contentType
                            qualConfig
                            today
                in
                uploadFileHttpTask
                    { url = url
                    , file = fileData.file
                    , parts = parts
                    , key = key
                    , bucket = record.bucket
                    , maybeTimeout = record.maybeTimeout
                    }
            )


{-| Upload file via `Http.request`. Useful if you want to get the `tracker` but you must provide your own `Time.now` due to limitations with `Http` + `Task`.
-}
uploadFileHttp :
    { toMsg : Result Http.Error Response -> msg
    , maybeTracker : Maybe String
    , now : Posix
    }
    -> FileData
    -> Config
    -> Cmd msg
uploadFileHttp { maybeTracker, now, toMsg } fileData ((Internals.Config record) as qualConfig) =
    let
        url =
            Internals.makeUrl qualConfig

        key =
            Internals.buildUploadKey
                { prefix = record.prefix
                , fileName = fileData.fileName
                }

        parts =
            Internals.generatePolicy key
                fileData.contentType
                qualConfig
                now
    in
    uploadFileHttpRequest toMsg
        { url = url
        , file = fileData.file
        , parts = parts
        , key = key
        , bucket = record.bucket
        , maybeTimeout = record.maybeTimeout
        , maybeTracker = maybeTracker
        }


uploadFileHttpTask :
    { url : String
    , file : File
    , parts : List Http.Part
    , key : String
    , bucket : String
    , maybeTimeout : Maybe Float
    }
    -> Task Http.Error Response
uploadFileHttpTask record =
    Http.riskyTask
        { method = "POST"
        , headers = []
        , url = record.url
        , body = Http.multipartBody (record.parts ++ [ Http.filePart "file" record.file ])
        , resolver = Http.bytesResolver (expectedResponse record)
        , timeout = record.maybeTimeout
        }


uploadFileHttpRequest :
    (Result Http.Error Response -> msg)
    ->
        { url : String
        , file : File
        , parts : List Http.Part
        , key : String
        , bucket : String
        , maybeTimeout : Maybe Float
        , maybeTracker : Maybe String
        }
    -> Cmd msg
uploadFileHttpRequest toMsg record =
    Http.riskyRequest
        { method = "POST"
        , headers = []
        , url = record.url
        , body = Http.multipartBody (record.parts ++ [ Http.filePart "file" record.file ])
        , expect = Http.expectBytesResponse toMsg (expectedResponse record)
        , timeout = record.maybeTimeout
        , tracker = record.maybeTracker
        }


expectedResponse :
    { r | bucket : String, key : String }
    -> Http.Response Bytes
    -> Result Http.Error Response
expectedResponse record response =
    case response of
        Http.BadUrl_ badUrl ->
            Err (Http.BadUrl badUrl)

        Http.Timeout_ ->
            Err Http.Timeout

        Http.NetworkError_ ->
            Err Http.NetworkError

        Http.BadStatus_ metadata _ ->
            Err (Http.BadStatus metadata.statusCode)

        Http.GoodStatus_ metadata _ ->
            let
                headerGet : String -> Http.Error -> Result Http.Error String
                headerGet key missingErr =
                    Result.fromMaybe missingErr (Dict.get key metadata.headers)
            in
            Result.map2
                (\etag location ->
                    { etag = String.replace "\"" "" etag
                    , location = location
                    , bucket = record.bucket
                    , key = record.key
                    }
                )
                (headerGet "etag" (Http.BadBody "ETag missing on response header"))
                (headerGet "location" (Http.BadBody "Location missing on response header"))



-- Fallback Values --


awsS3Host : String
awsS3Host =
    "s3.amazonaws.com"


awsAcl : String
awsAcl =
    "public-read"


successActionStatus : Int
successActionStatus =
    201
