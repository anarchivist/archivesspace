class NameCorporateEntity < Sequel::Model(:name_corporate_entity)
  include ASModel
  corresponds_to JSONModel(:name_corporate_entity)

  include AgentNames

  include AutoGenerator

  auto_generate :property => :sort_name,
                :generator => proc  { |json|
                  result = ""

                  result << "#{json["primary_name"]}" if json["primary_name"]
                  result << ". #{json["subordinate_name_1"]}" if json["subordinate_name_1"]
                  result << ". #{json["subordinate_name_2"]}" if json["subordinate_name_2"]

                  grouped = [json["number"], json["dates"]].reject{|v| v.nil?}
                  result << " (#{grouped.join(" : ")})" if not grouped.empty?

                  result << " (#{json["qualifier"]})" if json["qualifier"]

                  result.length > 255 ? result[0..254] : result
                },
                :only_if => proc { |json| json["sort_name_auto_generate"] }

end
