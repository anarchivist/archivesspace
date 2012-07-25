class RepositoryController < ApplicationController

  def new
    @repository = Repository.new({})
    render :layout=>nil
  end
  
  def create
    begin
      @repository = Repository.from_hash(params['repository'])
    rescue JSONModel::JSONValidationException => e
      @repository = e.invalid_object
      @errors = e.errors      
      return render action: "new", :layout=>nil
    end
    
    response = @repository.save

    if response['status'] === "Created"
      render :text=>"Success"
    else
      return render action: "new", :layout=>nil
    end
  end
  
  def select    
    session[:repo] = Repository.find(params[:id])
    render :partial=>'shared/header_repository'
  end
  
end