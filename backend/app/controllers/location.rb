class ArchivesSpaceService < Sinatra::Base

  Endpoint.post('/locations/batch')
  .description("Create a Batch of Locations")
  .params(["dry_run", BooleanParam, "If true, don't create the locations, just list them", :optional => true],
          ["location_batch", JSONModel(:location_batch), "The location batch data to generate all locations", :body => true])
  .permissions([:update_location_record])
  .returns([200, :updated]) \
  do
    batch = params[:location_batch]

    if params[:dry_run]
      result = Location.titles_for_batch(batch)
    else
      result = Location.create_for_batch(batch).map {|obj| obj.uri}
    end

    json_response(result)
  end

  Endpoint.post('/locations/:id')
  .description("Update a Location")
  .params(["id", :id],
          ["location", JSONModel(:location), "The updated record", :body => true])
    .permissions([:update_location_record])
  .returns([200, :updated]) \
  do
    handle_update(Location, params[:id], params[:location])
  end

  Endpoint.post('/locations')
    .description("Create a Location")
    .params(["location", JSONModel(:location), "The record to create", :body => true])
    .permissions([:update_location_record])
    .returns([200, :created]) \
  do
    handle_create(Location, params[:location])
  end


  Endpoint.get('/locations')
    .description("Get a list of locations")
    .params()
    .paginated(true)
    .permissions([])
    .returns([200, "[(:location)]"]) \
  do
    handle_listing(Location, params)
  end


  Endpoint.get('/locations/:id')
    .description("Get a Location by ID")
    .params(["id", :id])
    .permissions([])
    .returns([200, "(:location)"]) \
  do
    json_response(Location.to_jsonmodel(params[:id]))
  end

end
