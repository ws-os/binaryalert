// Downloader queue - MD5s to download from CarbonBlack
resource "aws_sqs_queue" "downloader_queue" {
  count = "${var.enable_carbon_black_downloader}"
  name  = "${var.name_prefix}_binaryalert_downloader_queue"

  // When a message is received, it will be hidden from the queue for this long.
  // Set to just a few seconds after the downloader would timeout.
  visibility_timeout_seconds = "${format("%d", var.lambda_download_timeout_sec + 2)}"

  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.sqs_dlq.arn}\",\"maxReceiveCount\":${var.download_queue_max_receives}}"

  tags {
    Name = "${var.tagged_name}"
  }
}

// Analysis queue - S3 objects which need to be analyzed
resource "aws_sqs_queue" "s3_object_queue" {
  name = "${var.name_prefix}_binaryalert_s3_object_queue"

  // When a message is received, it will be hidden from the queue for this long.
  // Set to just a few seconds after the lambda analyzer would timeout.
  visibility_timeout_seconds = "${format("%d", var.lambda_analyze_timeout_sec + 2)}"

  redrive_policy = "{\"deadLetterTargetArn\":\"${aws_sqs_queue.sqs_dlq.arn}\",\"maxReceiveCount\":${var.analysis_queue_max_receives}}"

  tags {
    Name = "${var.tagged_name}"
  }
}

data "aws_iam_policy_document" "s3_object_queue_policy" {
  statement {
    sid    = "AllowBinaryAlertBucketToNotifySQS"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions   = ["sqs:SendMessage"]
    resources = ["${aws_sqs_queue.s3_object_queue.arn}"]

    // Allow only the BinaryAlert S3 bucket to notify the SQS queue.
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["${aws_s3_bucket.binaryalert_binaries.arn}"]
    }
  }
}

// Allow SQS to be sent messages from the BinaryAlert S3 bucket.
resource "aws_sqs_queue_policy" "s3_object_queue_policy" {
  queue_url = "${aws_sqs_queue.s3_object_queue.id}"
  policy    = "${data.aws_iam_policy_document.s3_object_queue_policy.json}"
}

// Dead letter queue - messages which fail to be processed from SQS after X retries are sent here.
// Messages sent here are meant for human consumption (debugging) and are retained for 14 days.
resource "aws_sqs_queue" "sqs_dlq" {
  name                      = "${var.name_prefix}_binaryalert_sqs_dead_letter_queue"
  message_retention_seconds = 1209600

  tags {
    Name = "${var.tagged_name}"
  }
}
