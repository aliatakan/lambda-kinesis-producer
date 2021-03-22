import json
import boto3
import os
import csv

def send_kinesis(lines):
  kinesis_client = boto3.client('kinesis')
  stream_name = os.environ['stream_name']
  stream_shard_count = os.environ['stream_shard_count']
  kinesis_records = [] # empty list to store data
  row_count = 0
  total_row_count = len(lines) - 1
  send_kinesis = False 

  data = csv.DictReader(lines)
  
  for line in list(data):
    encodedValues = bytes(str(line), 'utf-8') # encode the string to bytes

    # create a dict object of the row
    kinesisRecord = {
        "Data": encodedValues, 
        "PartitionKey": str(stream_shard_count) 
    }

    kinesis_records.append(kinesisRecord)

    if len(kinesis_records) == 500: 
        send_kinesis = True 

    if row_count == total_row_count - 1: 
        send_kinesis = True 

    if send_kinesis == True:
        
        # put the records to kinesis stream
        response = kinesis_client.put_records(
            Records=kinesis_records,
            StreamName = stream_name
        )
        
        # resetting values ready for next loop
        kinesis_records = [] 
        send_kinesis = False 

    row_count = row_count + 1
  
  print('Sent to Kinesis: {0}'.format(total_row_count)) 

def lambda_handler(event, context):
    
    try:
      s3_client = boto3.client("s3")
      bucket_name = event['Records'][0]['s3']['bucket']['name']
      file_name = event['Records'][0]['s3']['object']['key']
      fileObject = s3_client.get_object(Bucket=bucket_name, Key=file_name)
      lines = fileObject['Body'].read().decode("cp437").splitlines(True)
      

      # send to kinesis
      send_kinesis(lines) 
    
    except Exception as e:
      print('Reason:', e)  