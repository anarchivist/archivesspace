require 'spec_helper'

describe 'Event model' do

  it "enforces at least one linked agent and one linked record via its schema" do

    expect {
      create(:json_event, :linked_records => [])
    }.to raise_error(JSONModel::ValidationException)

    expect {
      create(:json_event, :linked_agents => [])
    }.to raise_error(JSONModel::ValidationException)   
    
    expect {
      create(:json_event)
    }.to_not raise_error(JSONModel::ValidationException)
    
  end


  it "permits a mixture of linked record types" do
    
    opts = {:linked_records => []}
    
    [:resource, :accession, :archival_object].each do |type|
      record = create("json_#{type}".intern)
      opts[:linked_records].push({'ref' => record.uri, 'role' => generate(:record_role)})
    end
    
    expect {
      create(:json_event, opts)
    }.to_not raise_error(JSONModel::ValidationException)   

  end


  it "but not any old record type!" do
    
    opts = {:linked_records => [{'ref' => JSONModel(:repository).uri_for(2), 'role' => generate(:record_role)}]}
    
    expect {
      create(:json_event, opts)
    }.to raise_error(JSONModel::ValidationException)
  end

end
