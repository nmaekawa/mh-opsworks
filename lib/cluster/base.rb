module Cluster
  class Base
    require 'uri'
    require 'json'
    include ConfigurationHelpers
    include NamingHelpers
    include ClientHelpers

    def self.with_encoded_document
      JSON.dump(
        yield
      )
    end

    def self.json_encode(string)
      JSON.dump(string)
    end

    # Allows the construction of client interfaces at the instance level
    def construct_instance(instance_id)
      self.class.construct_instance(instance_id)
    end

    def self.instance_profile_policy_document
      with_encoded_document do
        {
          "Statement" =>  [
            {
              "Action" =>  [
                "cloudwatch:*",
                "sns:CreateTopic"
              ],
              "Effect" => "Allow",
              "Resource" => [
                "*"
              ]
            }
          ]
        }
      end
    end

    def self.instance_profile_assume_role_policy_document
      with_encoded_document do
        {
          "Version" => "2008-10-17",
          "Statement" => [
            {
              "Sid" => "",
              "Effect" => "Allow",
              "Principal" => {
                "Service" => "ec2.amazonaws.com"
              },
              "Action" => "sts:AssumeRole"
            }
          ]
        }
      end
    end

    def self.service_role_policy_document
      with_encoded_document do
        {
          "Statement" =>  [
            {
              "Action" =>  [
                "ec2:*",
                "iam:PassRole",
                "cloudwatch:GetMetricStatistics",
                "elasticloadbalancing:*",
                "rds:*"
              ],
              "Effect" => "Allow",
              "Resource" => [
                "*"
              ] 
            }
          ]
        }
      end
    end

    def self.assume_role_policy_document
      with_encoded_document do
        {
          "Version" => "2008-10-17",
          "Statement" => [
            {
              "Sid" => "",
              "Effect" => "Allow",
              "Principal" => {
                "Service" => "opsworks.amazonaws.com"
              },
              "Action" => "sts:AssumeRole"
            }
          ]
        }
      end
    end
  end
end
