public class AWSUtility {
    public String awsKey;
    public String awsSecret;
    public String bucketName;
    public String methodName;
    public String hostName;

    public AWSUtility(String key, String sec, String bkt, String method, String host) {
        this.awsKey = key;
        this.awsSecret = sec;
        this.bucketName = bkt;
        this.methodName = method;
        this.hostName = host;
    }

    public String contentType(String fileType) {
        switch on fileType.toLowerCase() {
            when 'csv' { return 'text/csv'; }
            when 'docx', 'doc' { return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'; }
            when 'wav' { return 'audio/wav'; }
            when 'png' { return 'image/png'; }
            when 'pdf' { return 'application/pdf'; }
            when else { return 'image/jpeg'; }
        }
    }

    public String createAuthHeader(String contentType, String formattedDateString, String canonicalizedResource) {
        // Without x-amz-acl, stringToSign is much cleaner
        String stringToSign = this.methodName + '\n' +
                             '' + '\n' + // Content-MD5
                             contentType + '\n' +
                             formattedDateString + '\n' +
                             canonicalizedResource;

        Blob mac = Crypto.generateMac(
            'hmacSHA1',
            Blob.valueOf(stringToSign),
            Blob.valueOf(this.awsSecret)
        );

        return 'AWS ' + this.awsKey + ':' + EncodingUtil.base64Encode(mac);
    }

    public void uploadDocuments(String recordId) {
        List<ContentDocumentLink> contentLinkList = [
            SELECT ContentDocumentId 
            FROM ContentDocumentLink 
            WHERE LinkedEntityId = :recordId
        ];

        Set<Id> conDocIdSet = new Set<Id>();
        for (ContentDocumentLink link : contentLinkList) {
            conDocIdSet.add(link.ContentDocumentId);
        }

        List<ContentVersion> cVersions = [
            SELECT VersionData, Title, FileExtension 
            FROM ContentVersion 
            WHERE ContentDocumentId IN :conDocIdSet AND IsLatest = true
        ];

        for (ContentVersion attach : cVersions) {
            String objectKey = attach.Title.replaceAll('\\s+', '_').toLowerCase() + '.' + attach.FileExtension.toLowerCase();
            String formattedDateString = DateTime.now().formatGmt('EEE, dd MMM yyyy HH:mm:ss') + ' GMT';
            String mimeType = contentType(attach.FileExtension);

            String canonicalizedResource = '/' + this.bucketName + '/' + objectKey;
            String fileUrl = 'https://' + this.bucketName + '.' + this.hostName + '/' + objectKey;

            HttpRequest req = new HttpRequest();
            req.setMethod(this.methodName);
            req.setEndpoint(fileUrl);

            // Headers
            req.setHeader('Host', this.bucketName + '.' + this.hostName);
            req.setHeader('Content-Type', mimeType);
            req.setHeader('Date', formattedDateString);

            req.setBodyAsBlob(attach.VersionData);

            // Auth Header
            String authHeader = createAuthHeader(mimeType, formattedDateString, canonicalizedResource);
            req.setHeader('Authorization', authHeader);

            Http h = new Http();
            HttpResponse res = h.send(req);

            System.debug('Response Status Code: ' + res.getStatusCode());
            System.debug('Response Body: ' + res.getBody());
        }
    }
}