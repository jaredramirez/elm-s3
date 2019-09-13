module S3 exposing
    ( Config, config, withPrefix, withSuccessActionStatus, withAwsS3Host, withAcl
    , FileData, Response, uploadFile, uploadFileTask
    )

{-| This package is built to make uploading file to [Amazon S3](https://aws.amazon.com/s3/)
quick and easy.

Before looking at how to use this package, there's a few things to note about S3 permissions.

1.Make sure that your user's IAM policy and the bucket policy provides access
to the bucket (and path prefix) you want to upload too. Take a look [at AWS's docs](https://docs.aws.amazon.com/AmazonS3/latest/dev/example-policies-s3.html) for a few examples.

1.  If you use this package and run into issues with CORs. Try setting the CORs configuration on
    your bucket to something like:

    """
    <CORSConfiguration>
    <CORSRule>
    <AllowedOrigin><http://myAmazingSite.com</AllowedOrigin>>>
    <AllowedMethod>POST</AllowedMethod>
    <ExposeHeader>ETag</ExposeHeader>
    <ExposeHeader>Location</ExposeHeader>
    <AllowedHeader>\*</AllowedHeader>
    </CORSRule>
    </CORSConfiguration>
    """

Note the `AllowedOrigin` tag and `AllowedHeader` tag, which should fix the CORs problem
but **also make sure to add both the `ExposeHeader` options. The upload request in
this library will fail without them.** If you don't have any CORs issues, don't worry about this.

With that taken care of, let's dive straight in!

First, you need to create some configuration for the request. This configuration holds data
that's needed across all upload requests, so if you need to upload files in multiple places
across your application, then you can create this config once and use it all over

    import S3

    s3Config : S3.Config
    s3Config =
        S3.config
            { accessKey = "..." -- AWS Access Key
            , secretKey = "..." -- AWS Secret Key
            , bucket = "my-bucket"
            , region = "us-east-2"
            }
            |> S3.withPrefix "invoices/"

Next, you need to get a file. You can do this with core [`File`](https://package.elm-lang.org/packages/elm/file/latest/File-Select) package. Take a look at it's documentation to see how to get a file from the user. Once you
have it. You can upload the file!

    import Http
    import File exposing (File)
    import S3

    type Msg
        = ...
        | FileLoaded File
        | SetFileRequest (Result Http.Error S3.Response)


    update : Msg -> Model -> (Model, Cmd Msg)
    update msg model =
        case msg of

            ...

            FileLoaded file->
                ( model
                , S3.uploadFile
                    { fileName = "customerInvoice.pdf"
                    , contentType = "application/pdf"
                    , file = file
                    }
                    s3Config
                    SetFileRequest
                )

            SetFileRequest result ->
                case result of
                    Err httpError ->
                        -- Handle the error
                        ...

                    Ok {location} ->
                        -- Do something with uploaded file path!
                        -- Maybe display it to the user, maybe
                        -- upload it to your server.
                        -- The world is your oyseter!
                        ...

And that's it!


# Creating a Config

@docs Config, config, withPrefix, withSuccessActionStatus, withAwsS3Host, withAcl


# Uploading a file

@docs FileData, Response, uploadFile, uploadFileTask

-}

import Dict
import File exposing (File)
import Http
import S3.Internals as Internals
import String.Interpolate exposing (interpolate)
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
    prefix
        |> (\p ->
                if String.endsWith "/" p then
                    String.dropRight 1 p

                else
                    p
           )


{-| Add a custom acl (Access Control List) for the uploaded document.
**This defaults to `public-read`**

    config |> withAcl "private"

-}
withAcl : String -> Config -> Config
withAcl prefix (Internals.Config record) =
    Internals.Config { record | prefix = prefix }


{-| Add a cusotm success HTTP status. This defaults to `201`.

    config |> withSuccessActionStatus 200

-}
withSuccessActionStatus : Int -> Config -> Config
withSuccessActionStatus int (Internals.Config record) =
    Internals.Config { record | successActionStatus = int }



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
uploadFile : FileData -> Config -> (Result Http.Error Response -> msg) -> Cmd msg
uploadFile fileData qualConfig toMsg =
    uploadFileTask fileData qualConfig
        |> Task.attempt toMsg


{-| Upload a file but as a task. This is helpful if you need to upload a file, then
get it's location from the [`Response`](#Response) and set that on your server.
-}
uploadFileTask : FileData -> Config -> Task Http.Error Response
uploadFileTask fileData ((Internals.Config record) as qualConfig) =
    Time.now
        |> Task.andThen
            (\today ->
                let
                    url =
                        interpolate """https://{0}.{1}"""
                            [ record.bucket
                            , record.awsS3Host
                            ]

                    key =
                        interpolate "{0}/{1}"
                            [ record.prefix
                            , fileData.fileName
                            ]

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
                    }
            )


uploadFileHttpTask :
    { url : String
    , file : File
    , parts : List ( String, String )
    , key : String
    , bucket : String
    }
    -> Task Http.Error Response
uploadFileHttpTask { url, file, parts, key, bucket } =
    Http.riskyTask
        { method = "POST"
        , headers =
            []
        , url = url
        , body =
            Http.multipartBody
                (List.map (\( a, b ) -> Http.stringPart a b) parts
                    ++ [ Http.filePart "file" file ]
                )
        , resolver =
            Http.bytesResolver
                (\response ->
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
                            Maybe.map2
                                (\etag location ->
                                    { etag = etag |> String.replace "\"" ""
                                    , location = location
                                    , bucket = bucket
                                    , key = key
                                    }
                                )
                                (Dict.get "etag" metadata.headers)
                                (Dict.get "location" metadata.headers)
                                |> Result.fromMaybe
                                    (Http.BadBody "ETag or Location missing on response header")
                )
        , timeout = Nothing
        }



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
