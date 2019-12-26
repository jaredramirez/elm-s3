module S3.Internals exposing
    ( Config(..)
    , Policy
    ,  buildUploadKey
       -- Exposed for testing

    , generatePolicy
    ,  makePolicy
       -- Exposed for testing

    , makeSignature
    ,  strToBase64
       -- Exposed for testing

    )

import Base64.Encode
import Crypto.HMAC
import Iso8601
import Json.Encode
import Time exposing (Posix)
import Word.Bytes as WordBytes
import Word.Hex as Hex


type Config
    = Config
        { awsAccessKey : String
        , awsSecretKey : String
        , bucket : String
        , region : String
        , awsS3Host : String
        , prefix : String
        , acl : String
        , successActionStatus : Int
        }



-- Path --


buildUploadKey : { prefix : String, fileName : String } -> String
buildUploadKey { prefix, fileName } =
    case prefix of
        "" ->
            fileName

        _ ->
            normalizePath prefix ++ "/" ++ normalizePath fileName


normalizePath : String -> String
normalizePath =
    stripLeadingSlashes >> stripTrailingSlashes


stripLeadingSlashes : String -> String
stripLeadingSlashes str =
    if String.startsWith "/" str then
        String.dropLeft 1 str

    else
        str


stripTrailingSlashes : String -> String
stripTrailingSlashes str =
    if String.endsWith "/" str then
        String.dropRight 1 str

    else
        str



-- Policy --


type alias Policy =
    { expirationDate : Posix
    , bucket : String
    , key : String
    , acl : String
    , successActionStatus : Int
    , contentType : String
    , amzCredential : String
    , amzAlgorithm : String
    , amzDate : String
    , yyyymmddDate : String
    }



-- Policy --


generatePolicy : String -> String -> Config -> Time.Posix -> List ( String, String )
generatePolicy fullFilePath contentType qualConfig today =
    let
        policy =
            makePolicy today contentType fullFilePath qualConfig

        base64Policy =
            policy
                |> policyToJson
                |> Json.Encode.encode 0
                |> strToBase64

        signature =
            makeSignature base64Policy policy qualConfig
    in
    generatePolicyParts
        { base64Policy = base64Policy
        , signature = signature
        , policy = policy
        , contentType = contentType
        }
        qualConfig


generatePolicyParts :
    { base64Policy : String
    , signature : String
    , policy : Policy
    , contentType : String
    }
    -> Config
    -> List ( String, String )
generatePolicyParts { base64Policy, signature, policy, contentType } (Config record) =
    [ ( "key", policy.key )
    , ( "acl", record.acl )
    , ( "success_action_status"
      , record.successActionStatus |> String.fromInt
      )
    , ( "Content-Type", contentType )
    , ( "X-Amz-Credential", policy.amzCredential )
    , ( "X-Amz-Algorithm", policy.amzAlgorithm )
    , ( "X-Amz-Date", policy.amzDate )
    , ( "Policy", base64Policy )
    , ( "X-Amz-Signature", signature )
    ]


makePolicy : Time.Posix -> String -> String -> Config -> Policy
makePolicy today contentType fullFilePath (Config record) =
    let
        yyyymmddDate =
            today
                |> Iso8601.fromTime
                |> String.slice 0 10
                |> String.replace "-" ""
    in
    { expirationDate =
        Time.posixToMillis today
            + fiveMinutes
            |> Time.millisToPosix
    , bucket = record.bucket
    , key = fullFilePath
    , acl = record.acl
    , successActionStatus = record.successActionStatus
    , contentType = contentType
    , amzCredential =
        String.join "/"
            [ record.awsAccessKey
            , yyyymmddDate
            , record.region
            , awsServiceName
            , awsRequestPolicyVersion
            ]
    , amzAlgorithm = awsAlgorithm
    , amzDate = yyyymmddDate ++ "T000000Z"
    , yyyymmddDate = yyyymmddDate
    }


strToBase64 : String -> String
strToBase64 str =
    str
        |> Base64.Encode.string
        |> Base64.Encode.encode


policyToJson : Policy -> Json.Encode.Value
policyToJson policy =
    Json.Encode.object
        [ ( "expiration"
          , policy.expirationDate |> Iso8601.fromTime |> Json.Encode.string
          )
        , ( "conditions"
          , [ Json.Encode.object
                [ ( "bucket", Json.Encode.string policy.bucket ) ]
            , Json.Encode.object
                [ ( "key", Json.Encode.string policy.key ) ]
            , Json.Encode.object
                [ ( "acl", Json.Encode.string policy.acl ) ]
            , Json.Encode.object
                [ ( "success_action_status"
                  , policy.successActionStatus
                        |> String.fromInt
                        |> Json.Encode.string
                  )
                ]
            , Json.Encode.object
                [ ( "Content-Type", Json.Encode.string policy.contentType ) ]
            , Json.Encode.object
                [ ( "x-amz-credential", Json.Encode.string policy.amzCredential ) ]
            , Json.Encode.object
                [ ( "x-amz-algorithm", Json.Encode.string policy.amzAlgorithm ) ]
            , Json.Encode.object
                [ ( "x-amz-date", Json.Encode.string policy.amzDate ) ]
            ]
                |> Json.Encode.list identity
          )
        ]



-- Signature --


makeSignature : String -> Policy -> Config -> String
makeSignature base64EncodedPolicy policy (Config record) =
    let
        digest message key =
            Crypto.HMAC.digestBytes Crypto.HMAC.sha256 key (WordBytes.fromUTF8 message)
    in
    ("AWS4" ++ record.awsSecretKey)
        |> WordBytes.fromUTF8
        |> digest policy.yyyymmddDate
        |> digest record.region
        |> digest awsServiceName
        |> digest awsRequestPolicyVersion
        |> digest base64EncodedPolicy
        |> Hex.fromByteList



-- Constants --


fiveMinutes : Int
fiveMinutes =
    5 * (60 * 1000)


awsServiceName : String
awsServiceName =
    "s3"


awsRequestPolicyVersion : String
awsRequestPolicyVersion =
    "aws4_request"


awsAlgorithm : String
awsAlgorithm =
    "AWS4-HMAC-SHA256"
