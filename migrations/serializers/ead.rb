require 'nokogiri'
require 'securerandom'

class RawXMLHandler

  def initialize
    @fragments = {}
  end

  def <<(s)
    id = SecureRandom.hex
    @fragments[id] = s

    ":aspace_fragment_#{id}"
  end

  def substitute_fragments(xml_string)
    @fragments.each do |id, fragment|
      xml_string.gsub!(/:aspace_fragment_#{id}/, fragment)
      xml_string.gsub!(/[&]([^a])/, '&amp;\1')
    end

    xml_string
  end
end


class StreamHandler

  def initialize
    @sections = {}
    @depth = 0
  end


  def buffer(&block)
    id = SecureRandom.hex
    @sections[id] = block
    ":aspace_section_#{id}_"
  end


  def stream_out(doc, fragments, y, depth=0)
    xml_text = doc.to_xml
    xml_text.force_encoding('utf-8')
    queue = xml_text.split(":aspace_section")

    y << fragments.substitute_fragments(queue.shift)

    while queue.length > 0
      next_section = queue.shift
      next_id = next_section.slice!(/^_(\w+)_/).gsub(/_/, '')
      next_fragments = RawXMLHandler.new
      doc_frag = Nokogiri::XML::DocumentFragment.parse ""
      Nokogiri::XML::Builder.with(doc_frag) do |xml|
        @sections[next_id].call(xml, next_fragments)
      end
      stream_out(doc_frag, next_fragments, y, depth + 1)

      if next_section && !next_section.empty?
        y << fragments.substitute_fragments(next_section)
      end
    end
  end
end


ASpaceExport::serializer :ead do

  def stream(data)

    @stream_handler = StreamHandler.new
    @fragments = RawXMLHandler.new

    doc = Nokogiri::XML::Builder.new do |xml|

      xml.ead('xmlns' => 'urn:isbn:1-931666-22-9',
                 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
                 'xsi:schemaLocation' => 'urn:isbn:1-931666-22-9 http://www.loc.gov/ead/ead.xsd',
                 'xmlns:xlink' => 'http://www.w3.org/1999/xlink') {

        xml.text (
          @stream_handler.buffer { |xml, new_fragments|
            serialize_eadheader(data, xml, new_fragments)
          })

        atts = {:level => data.level, :otherlevel => data.other_level}
        atts.reject! {|k, v| v.nil?}

        xml.archdesc(atts) {

          data.digital_objects.each do |dob|
            serialize_digital_object(dob, xml, @fragments)
          end

          xml.did {

            if (val = data.language)
              xml.langmaterial {
                xml.language(:langcode => val) {
                  xml.text I18n.t("enumerations.language_iso639_2.#{val}", :default => val)
                }
              }
            end

            if (val = data.repo.name)
              xml.repository {
                xml.corpname val
              }
            end

            if (val = data.title)
              xml.unittitle val
            end

            serialize_origination(data, xml, @fragments)

            xml.unitid (0..3).map{|i| data.send("id_#{i}")}.compact.join('.')

            serialize_extents(data, xml, @fragments)

            serialize_dates(data, xml, @fragments)

            serialize_did_notes(data, xml, @fragments)

            data.instances_with_containers.each do |instance|
              serialize_container(instance, xml, @fragments)
            end

          }# </did>

          serialize_nondid_notes(data, xml, @fragments)

          serialize_bibliographies(data, xml, @fragments)

          serialize_indexes(data, xml, @fragments)

          serialize_controlaccess(data, xml, @fragments)

          xml.dsc {

            data.children_indexes.each do |i|
              xml.text(
                @stream_handler.buffer {|xml, new_fragments|
                  serialize_child(data.get_child(i), xml, new_fragments)
                }
              )
            end
          }
        }
      }
    end

    Enumerator.new do |y|
      @stream_handler.stream_out(doc, @fragments, y)
    end
  end


  def serialize_child(data, xml, fragments)
    prefixed_ref_id = "#{I18n.t('archival_object.ref_id_export_prefix', :default => 'aspace_')}#{data.ref_id}"
    atts = {:level => data.level, :otherlevel => data.other_level, :id => prefixed_ref_id}
    atts.reject! {|k, v| v.nil?}
    xml.c(atts) {

      xml.did {
        if (val = data.title)
          xml.unittitle val
        end

        if !data.component_id.nil? && !data.component_id.empty?
          xml.unitid data.component_id
        end

        serialize_origination(data, xml, fragments)
        serialize_extents(data, xml, fragments)
        serialize_dates(data, xml, fragments)
        serialize_did_notes(data, xml, fragments)

        # TODO: Clean this up more; there's probably a better way to do this.
        # For whatever reason, the old ead_containers method was not working
        # on archival_objects (see migrations/models/ead.rb).

        data.instances.each do |inst|
          case 
          when inst.has_key?('container') && !inst['container'].nil?
            serialize_container(inst, xml, fragments)
          when inst.has_key?('digital_object') && !inst['digital_object']['_resolved'].nil?
            serialize_digital_object(inst['digital_object']['_resolved'], xml, fragments)
          end
        end

      }

      serialize_nondid_notes(data, xml, fragments)

      serialize_bibliographies(data, xml, fragments)

      serialize_indexes(data, xml, fragments)

      serialize_controlaccess(data, xml, fragments)

      data.children_indexes.each do |i|
        xml.text(
          @stream_handler.buffer {|xml, new_fragments|
            serialize_child(data.get_child(i), xml, new_fragments)
          }
        )
      end
    }
  end


  def serialize_origination(data, xml, fragments)
    unless data.creators_and_sources.nil?
      data.creators_and_sources.each do |link|
        agent = link['_resolved']
        role = link['role']
        relator = link['relator']
        sort_name = agent['names'][0]['sort_name']
        rules = agent['names'][0]['rules']
        source = agent['names'][0]['source']
        node_name = case agent['agent_type']
                    when 'agent_person'; 'persname'
                    when 'agent_family'; 'famname'
                    when 'agent_corporate_entity'; 'corpname'
                    end
        xml.origination(:label => role) {
         atts = {:relator => relator, :source => source, :rules => rules}
         atts.reject! {|k, v| v.nil?}

          xml.send(node_name, atts) {
            xml.text sort_name
          }
        }
      end
    end
  end

  def serialize_controlaccess(data, xml, fragments)
    if (data.controlaccess_subjects.length + data.controlaccess_linked_agents.length) > 0
      xml.controlaccess {

        data.controlaccess_subjects.each do |node_data|
          xml.send(node_data[:node_name], node_data[:atts]) {
            xml.text node_data[:content]
          }
        end


        data.controlaccess_linked_agents.each do |node_data|
          xml.send(node_data[:node_name], node_data[:atts]) {
            xml.text node_data[:content]
          }
        end

      } #</controlaccess>
    end
  end

  def serialize_subnotes(subnotes, xml, fragments)
    subnotes.each do |sn|

      title = sn['title']

      case sn['jsonmodel_type']
      when 'note_chronology'
        xml.chronlist {
          xml.head title if title

          sn['items'].each do |item|
            xml.chronitem {
              if (val = item['event_date'])
                xml.date val
              end
              if item['events'] && !item['events'].empty?
                xml.eventgrp {
                  item['events'].each do |event|
                    xml.event event
                  end
                }
              end
            }
          end
        }
      when 'note_orderedlist'
        atts = {:type => 'ordered', :numeration => sn['enumeration']}.reject{|k,v| v.nil? || v.empty?}
        xml.list(atts) {
          xml.head title if title

          sn['items'].each do |item|
            xml.item item
          end
        }
      when 'note_definedlist'
        xml.list(:type => 'deflist') {
          xml.head title if title

          sn['items'].each do |item|
            xml.defitem {
              xml.label item['label'] if item['label']
              xml.item item['value'] if item['value']
            } 
          end
        }
      end
    end
  end

  def serialize_container(inst, xml, fragments)
    containers = []
    (1..3).each do |n|
      atts = {}
      next unless inst['container'].has_key?("type_#{n}") && inst['container'].has_key?("indicator_#{n}")
      atts[:type] = inst['container']["type_#{n}"]
      text = inst['container']["indicator_#{n}"]
      if n == 1 && inst['instance_type']
        atts[:label] = I18n.t("enumerations.instance_instance_type.#{inst['instance_type']}", :default => inst['instance_type'])
      end
      xml.container(atts) {
        xml.text text
      }
    end
  end

  def serialize_digital_object(digital_object, xml, fragments)
    file_version = digital_object['file_versions'][0] || {}
    title = digital_object['title']
    date = digital_object['dates'][0] || {}
    atts = {}

    content = ""
    content << title if title
    content << ": " if date['expression'] || date['begin']
    if date['expression']
      content << date['expression']
    elsif date['begin']
      content << date['begin']
      if date['end'] != date['begin']
        content << "-#{date['end']}"
      end
    end

    atts['xlink:href'] = file_version['file_uri'] || digital_object['digital_object_id']
    atts['xlink:title'] = digital_object['title'] if digital_object['title']
    atts['xlink:actuate'] = file_version['xlink_actuate_attribute'] || 'onRequest'
    atts['xlink:show'] = file_version['xlink_show_attribute'] || 'new'

    xml.dao(atts) {
      xml.daodesc{ xml.p(content) } if content
    }
  end


  def serialize_extents(obj, xml, fragments)
    if obj.extents.length
      obj.extents.each do |e|
        xml.physdesc({:altrender => e['portion']}) {
          if e['number'] && e['extent_type']
            xml.extent({:altrender => 'materialtype spaceoccupied'}) {
              xml.text "#{e['number']} #{I18n.t('enumerations.extent_extent_type.'+e['extent_type'], :default => e['extent_type'])}"
            }
          end
          if e['container_summary']
            xml.extent({:altrender => 'carrier'}) {
              xml.text e['container_summary']
            }
          end
          xml.physfacet e['physical_details'] if e['physical_details']
          xml.dimensions e['dimensions'] if e['dimensions']
        }
      end
    end
  end


  def serialize_dates(obj, xml, fragments)
    obj.archdesc_dates.each do |node_data|
      xml.unitdate(node_data[:atts]){
        xml.text node_data[:content]
      }
    end
  end


  def serialize_did_notes(data, xml, fragments)
    data.notes.each do |note|
      next unless data.did_note_types.include?(note['type'])

      content = ASpaceExport::Utils.extract_note_text(note)
      id = note['persistent_id']
      att = id ? {:id => id} : {}

      case note['type']
      when 'dimensions', 'physfacet'
        xml.physdesc {
          xml.send(note['type'], att) {
            xml.text (fragments << content)
          }
        }
      else
        xml.send(note['type'], att) {
          xml.text (fragments << content)
        }
      end
    end
  end

  def serialize_note_content(note, xml, fragments)
    content = ASpaceExport::Utils.extract_note_text(note)
    atts = {:id => note['persistent_id']}.reject{|k,v| v.nil? || v.empty?}
    head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
    xml.send(note['type'], atts) {
      xml.head head_text unless content.strip.start_with?('<head')
      if content.strip.start_with?('<')
        xml.text (fragments << content)
      else
        xml.p (fragments << content)
      end
      if note['subnotes']
        serialize_subnotes(note['subnotes'], xml, fragments)
      end
    }
  end


  def serialize_nondid_notes(data, xml, fragments)
    data.notes.each do |note|
      next if note['internal']
      next if note['type'].nil?
      next unless data.archdesc_note_types.include?(note['type'])
      if note['type'] == 'legalstatus'
        xml.accessrestrict {
          serialize_note_content(note, xml, fragments) 
        }
      else
        serialize_note_content(note, xml, fragments)
      end
    end
  end


  def serialize_bibliographies(data, xml, fragments)
    data.bibliographies.each do |note|
      content = ASpaceExport::Utils.extract_note_text(note)
      head_text = note['label'] ? note['label'] : I18n.t("enumerations._note_types.#{note['type']}")
      atts = {:id => note['persistent_id']}.reject{|k,v| v.nil? || v.empty?}

      xml.bibliography(atts) {
        xml.head head_text unless content.strip.start_with?('<head')
        if content.strip.start_with?('<')
          xml.text (fragments << content)
        else
          xml.p (fragments << content)
        end
        note['items'].each do |item|
          xml.bibref item unless item.empty?
        end
      }
    end
  end


  def serialize_indexes(data, xml, fragments)
    data.indexes.each do |note|
      content = ASpaceExport::Utils.extract_note_text(note)
      head_text = nil
      if note['label']
        head_text = note['label']
      elsif note['type']
        head_text = I18n.t("enumerations._note_types.#{note['type']}", :default => note['type'])
      end

      atts = {:id => note['persistent_id']}.reject{|k,v| v.nil? || v.empty?}

      xml.index(atts) {
        xml.head head_text unless content.strip.start_with?('<head')
        if content.strip.start_with?('<')
          xml.text (@fragments << content)
        else
          xml.p (@fragments << content)
        end
        note['items'].each do |item|
          next unless (node_name = data.index_item_type_map[item['type']])
          xml.indexentry {
            atts = item['reference'] ? {:target => item['reference']} : {}
            if (val = item['reference_text'])
              xml.ref(atts) {
                xml.text val
              }
            end
            if (val = item['value'])
              xml.send(node_name, val)
            end
          }
        end
      }
    end
  end


  def serialize_eadheader(data, xml, fragments)
    eadheader_atts = {:findaidstatus => data.finding_aid_status,
                      :repositoryencoding => "iso15511",
                      :countryencoding => "iso3166-1",
                      :dateencoding => "iso8601",
                      :langencoding => "iso639-2b"}.reject{|k,v| v.nil? || v.empty?}

    xml.eadheader(eadheader_atts) {

      eadid_atts = {:countrycode => data.repo.country,
              :url => data.ead_location,
              :mainagencycode => data.mainagencycode}.reject{|k,v| v.nil? || v.empty?}

      xml.eadid(eadid_atts) {
        xml.text data.ead_id
      }

      xml.filedesc {

        xml.titlestmt {

          titleproper = ""
          titleproper += "#{data.title} " if data.title
          titleproper += "<num>#{(0..3).map{|i| data.send("id_#{i}")}.compact.join('.')}</num>"
          xml.titleproper (fragments << titleproper)

          xml.author data.finding_aid_author unless data.finding_aid_author.nil?
          xml.sponsor data.finding_aid_sponsor unless data.finding_aid_sponsor.nil?
        }

        unless data.finding_aid_edition_statement.nil?
          xml.editionstmt {
            xml.p data.finding_aid_edition_statement
          }
        end

        xml.publicationstmt {
          xml.publisher data.repo.name

          if data.repo.image_url
            xml.p {
              xml.extref ({"xlink:href" => data.repo.image_url,
                          "xlink:actuate" => "onLoad",
                          "xlink:show" => "embed",
                          "xlink:linktype" => "simple"})
            }
          end

          unless data.addresslines.empty?
            xml.address {
              data.addresslines.each do |line|
                xml.addressline line
              end
            }
          end
        }

        if (val = data.finding_aid_series_statement)
          xml.seriesstmt {
            if val.strip.start_with?('<')
              xml.text (fragments << val)
            else
              xml.p (fragments << val)
            end
          }
        end
      }

      xml.profiledesc {
        creation = "This finding aid was produced using ArchivesSpace on <date>#{Time.now}</date>."
        xml.creation (fragments << creation)

        if (val = data.finding_aid_language)
          xml.langusage (fragments << val)
        end

        if (val = data.descrules)
          xml.descrules val
        end
      }

      if data.finding_aid_revision_date || data.finding_aid_revision_description
        xml.revisiondesc {
          if data.finding_aid_revision_description.strip.start_with?('<')
            xml.text (fragments << data.finding_aid_revision_description)
          else
            xml.change {
              xml.date (fragments << data.finding_aid_revision_date) if data.finding_aid_revision_date
              xml.item (fragments << data.finding_aid_revision_description) if data.finding_aid_revision_description
            }
          end
        }
      end
    }
  end
end
