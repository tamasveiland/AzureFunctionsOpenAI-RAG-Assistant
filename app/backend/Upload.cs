using System.Net;
using HttpMultipartParser;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Azure.Functions.Worker.Extensions.OpenAI.Embeddings;
using Microsoft.Azure.Functions.Worker.Extensions.OpenAI.Search;


namespace sample.demo
{
    public class Upload
    {
        private readonly ILogger<Upload> _logger;

        public Upload(ILogger<Upload> logger)
        {
            _logger = logger;
        }

        public class QueueHttpResponse
        {
            [QueueOutput("filequeue", Connection = "queueConnection")]
            public QueuePayload QueueMessage { get; set; }
            public HttpResponseData HttpResponse { get; set; }
        }

        public class QueuePayload
        {
            public string FileName { get; set; }
        }

        public class SemanticSearchOutputResponse
        {
            [SemanticSearchOutput("AISearchEndpoint", "openai-index", CredentialSettingName = "SearchAPIKey", EmbeddingsModel = "%EMBEDDING_MODEL_DEPLOYMENT_NAME%")]
            public SearchableDocument? SearchableDocument { get; set; }
        }

/// <summary>
/// Uploads the file Azure Files and adds the file location to the queue message.
/// The file location is then retrieved by the queue trigger to embed the content by the EmbedContent function.
/// </summary>
/// <param name="req"></param>
/// <returns></returns>
        [Function("upload")]
        public static async Task<QueueHttpResponse> UploadFile(
            [HttpTrigger(AuthorizationLevel.Anonymous, Route = "upload")] HttpRequestData req)
        {
            // Read file from request
            var parsedFormBody = await MultipartFormDataParser.ParseAsync(req.Body);
            var file = parsedFormBody.Files[0];
            var reader = new StreamReader(file.Data);

            // Save to file share
            var fileShare = Environment.GetEnvironmentVariable("fileShare");
            var fileStream = File.Create(fileShare + file.FileName);
            reader.BaseStream.Seek(0, SeekOrigin.Begin);
            reader.BaseStream.CopyTo(fileStream);
            fileStream.Close();

            var responseData = req.CreateResponse(HttpStatusCode.OK);
            var result = "{\"success\":True,\"message\":\"Files processed successfully.\"}";
            await responseData.WriteAsJsonAsync(result, HttpStatusCode.OK);
   
            // Add file location to queue message
            var payload = new QueuePayload
            {
                FileName = fileShare + file.FileName
            };

            // Return queue message and response as output
            return new QueueHttpResponse
            {
                QueueMessage = payload,
                HttpResponse = responseData
            };
        }

        [Function("EmbedContent")]
            public static async Task<SemanticSearchOutputResponse> EmbedContent(
            [QueueTrigger("filequeue", Connection = "queueConnection")] QueuePayload queueItem,
            [EmbeddingsInput("{FileName}", InputType.FilePath, Model = "%EMBEDDING_MODEL_DEPLOYMENT_NAME%")] EmbeddingsContext embeddingsContext)
        {
            return new SemanticSearchOutputResponse
            {
                SearchableDocument = new SearchableDocument(queueItem.FileName, embeddingsContext)
            };

        }

    }
}
