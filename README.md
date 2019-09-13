# elm-s3

This package helps make uploading file to [Amazon S3](https://aws.amazon.com/s3/) quick and easy.

# Install

`elm install jaredramirez/elm-s3`

# Usage

First, you need to create some configuration for the request. This configuration holds data that's needed across all upload requests, so if you need to upload files in multiple places across your application, then you can create this config once and use it all over

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

Next, you need to get a file. You can do this with core [`File`](https://package.elm-lang.org/packages/elm/file/latest/File-Select) package. Take a look at it's documentation to see how to get a file from the user. Once you have it. You can upload the file!

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

# Note on tracking upload progress

Uploading to S3 requires getting the current time, so this implementation uses `Task` under the hood. Unfortunately, [you can't track progress on http tasks](https://github.com/elm/http/issues/61). I'm not sure if this is a really desired feature. If it is, please create an issue and I'll look into adding support for!

# S3 Permissions

There's a few things to note about S3 permissions.

1. Make sure that your user's IAM policy and the bucket policy provides access to the bucket (and path prefix) you want to upload too. Take a look [at AWS's docs](https://docs.aws.amazon.com/AmazonS3/latest/dev/example-policies-s3.html) for a few examples.

2. If you use this package and run into issues with CORs. Try setting the CORs configuration on your bucket to something like:
```
    <CORSConfiguration>
    <CORSRule>
    <AllowedOrigin>http://myAmazingSite.com</AllowedOrigin>>>
    <AllowedMethod>POST</AllowedMethod>
    <ExposeHeader>ETag</ExposeHeader>
    <ExposeHeader>Location</ExposeHeader>
    <AllowedHeader>\*</AllowedHeader>
    </CORSRule>
    </CORSConfiguration>
```
Note the `AllowedOrigin` tag and `AllowedHeader` tag, which should fix the CORs problem but **also make sure to add both the `ExposeHeader` options. The upload request in this library will fail without them.** If you don't have any CORs issues, don't worry about this.

With that taken care of, let's dive straight in!
