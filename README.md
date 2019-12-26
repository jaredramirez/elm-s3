# elm-s3

This package helps make uploading file to [Amazon S3](https://aws.amazon.com/s3/) quick and easy.

# Note on security (Please read)

**This package requires storing your AWS secret and access keys in your Elm code. Please note that there is a security concern with having copies of these keys downloaded to each client that uses your app.**

Probably the best way to do S3 uploads is to store your AWS keys safely on your server, when your user is authenticated generate [presigned URLs](https://docs.aws.amazon.com/AmazonS3/latest/dev/PresignedUrlUploadObject.html), send that back to the client, the upload to that URL.

That being said, this can be done less securely using only the browser. Because this package uses AWS secret and access keys, the best way to mitigate any risks is to make sure that your IAM user's policy only allows for `PutObject` and `PutObjectAcl` **and** only has access to the subdirectory within your bucket that want you upload files to.

My user's IAM policy looks like this:
```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject",
                "s3:PutObjectAcl"
            ],
            "Resource": [
                "arn:aws:s3:::my-bucket/uploads/*" // SPECIFY YOUR SUB DIRECTORY HERE
            ]
        }
    ]
}
```

If your keys fell into the wrong hands with this policy, the most access they'd have is the ability to upload and overwrite any files already uploaded. If you add unique IDs and timestamps to each filename that you upload, the possiblility of a file being overwritten become unlikely.

**Please takes this information into consideration before using this library and proceed with caution.**


# Install

`elm install jaredramirez/elm-s3`

# Usage

First, you need to create a config for the request. This configuration holds data that's needed across all upload requests, so if you need to upload files in multiple places across your app you can create this config once and use it all over.

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

Next, you need to get a file. You can do this with core [`File`](https://package.elm-lang.org/packages/elm/file/latest/File-Select) package. Take a look at it's documentation to see how to get a file from the user. Once you have it, you can upload the file!

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
                        -- Do something with uploaded file path! Maybe display it to the user,
                        -- maybe upload it to your server.
                        -- The world is your oyseter!
                        ...

And that's it!

# Note on tracking upload progress

Uploading to S3 requires getting the current time, so this implementation uses `Time.now`  and `Task` under the hood. Unfortunately, [you can't track progress on http tasks](https://github.com/elm/http/issues/61). I'm not sure how important this feature is to people. If it a high priority for you, please create an issue and I'll look into adding work around support for it!

# CORs issues

If you use this package and run into issues with CORs, try setting the CORs configuration on your bucket to something like:
```
    <CORSConfiguration>
      <CORSRule>
        <AllowedOrigin>http://myAmazingSite.com</AllowedOrigin>
        <AllowedMethod>POST</AllowedMethod>
        <ExposeHeader>ETag</ExposeHeader>
        <ExposeHeader>Location</ExposeHeader>
        <AllowedHeader>\*</AllowedHeader>
      </CORSRule>
    </CORSConfiguration>
```
Note the `AllowedOrigin` tag and `AllowedHeader` tag, which should fix the CORs problem but **also make sure to add both the `ExposeHeader` options. The upload request in this library will fail without them.** If you don't have any CORs issues, don't worry about this.

# Thanks

Thanks to [`react-native-aws3`](https://github.com/benjreinhart/react-native-aws3)! I've used that library before on a react-native app and wanted something similar in Elm. It's the basis for writing this package.
