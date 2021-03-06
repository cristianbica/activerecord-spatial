
module ActiveRecord
  module Associations #:nodoc:
    class SpatialAssociation < HasManyAssociation
      attr_reader :geom, :foreign_geom, :relationship, :scope_options

      def initialize(*args)
        super

        @geom = self.options[:geom]
        @foreign_geom = self.options[:foreign_geom]
        @relationship = self.options[:relationship].to_s
        @scope_options = (self.options[:scope_options] || {}).merge({
          :column => @foreign_geom
        })
      end
    end

    class Builder::Spatial < Builder::HasMany #:nodoc:
      SPATIAL_MACRO = :has_many

      VALID_SPATIAL_OPTIONS = [
        :geom, :foreign_geom, :relationship, :scope_options
      ].freeze

      INVALID_SPATIAL_OPTIONS = [
        :through, :source, :source_type, :dependent, :finder_sql, :counter_sql,
        :inverse_of
      ].freeze

      private
        def dependency_method_name
          "spatially_#{self.relationship}_dependent_for_#{name}"
        end
    end

    class Preloader #:nodoc:
      class SpatialAssociation < HasMany #:nodoc:
        SPATIAL_FIELD_ALIAS = '__spatial_ids__'
        SPATIAL_JOIN_NAME = '__spatial_ids_join__'
        SPATIAL_JOIN_QUOTED_NAME = %{"#{SPATIAL_JOIN_NAME}"}

        private
          def associated_records_by_owner
            owners_map = owners_by_key
            owner_keys = owners_map.keys.compact

            if klass.nil? || owner_keys.empty?
              records = []
            else
              sliced  = owner_keys.each_slice(model.connection.in_clause_length || owner_keys.size)
              records = sliced.map { |slice| records_for(slice) }.flatten
            end

            records_by_owner = Hash[owners.map { |owner| [owner, []] }]

            records.each do |record|
              record[SPATIAL_FIELD_ALIAS].split(',').each do |owner_key|
                owners_map[owner_key].each do |owner|
                  records_by_owner[owner] << record
                end
              end
            end

            records_by_owner
          end
        end

        def preloader_for_with_spatial(reflection)
          if reflection.options[:relationship]
            SpatialAssociation
          else
            preloader_for_without_spatial(reflection)
          end
        end
        alias_method_chain :preloader_for, :spatial
    end
  end

  module Reflection #:nodoc:
    class AssociationReflection < MacroReflection #:nodoc:
      def association_class_with_spatial
        if self.options[:relationship]
           Associations::SpatialAssociation
        else
          association_class_without_spatial
        end
      end
      alias_method_chain :association_class, :spatial
    end
  end
end

# ActiveRecord Spatial associations allow for +has_many+-style associations
# using spatial relationships.
#
# == Example
#
#   class Neighbourhood < ActiveRecord::Base
#     has_many_spatially :cities,
#       :relationship => :contains
#   end
#
#   class City < ActiveRecord::Base
#     has_many_spatially :neighbourhoods,
#       :relationship => :within
#   end
#
#   Neighbourhood.first.cities
#   #=> All cities that the neighbourhood is within
#
#   City.first.neighbourhoods
#   #=> All neighbourhoods contained by the city
#
#   City.includes(:neighbourhoods).first.neighbourhoods
#   #=> Eager loading works too
#
# Spatial associations can be set up using any of the relationships found in
# ActiveRecordSpatial::SpatialScopes::RELATIONSHIPS.
#
# == Options
#
# Many of the options available with standard +has_many+ associations will work
# with the exceptions of +:through+, +:source+, +:source_type+, +:dependent+,
# +:finder_sql+, +:counter_sql+, and +:inverse_of+.
#
# Polymorphic relationships can be used via the +:as+ option as in standard
# +:has_many+ relationships. Note that the default field for the geometry
# in these cases is "#{association_name}_geom" and can be overridden using
# the +:foreign_geom+ option.
#
# * +:relationship+ - sets the spatial relationship for the association.
#   Valid options can be found in ActiveRecordSpatial::SpatialScopes::RELATIONSHIPS.
#   The default value is +:intersects+.
# * +:geom+ - sets the geometry field for the association in the calling model.
#   The default value is +:the_geom+ as is often seen in PostGIS documentation.
# * +:foreign_geom+ - sets the geometry field for the association's foreign
#   table. The default here is again +:the_geom+.
# * +:scope_options+ - these are options passed directly to the SpatialScopes
#   module and as such the options are the same as are available there. The
#   default value here is <tt>{ :invert => true }</tt>, as we want our
#   spatial relationships to say "Foo spatially contains many Bars" and
#   therefore the relationship in SQL becomes
#   <tt>ST_contains("foos"."the_geom", "bars"."the_geom")</tt>.
#
# Note that you can modify the default geometry column name for all of
# ActiveRecordSpatial by setting it via ActiveRecordSpatia.default_column_name.
#
# == Caveats
#
# * You should consider spatial associations to be essentially readonly. Since
#   we're not dealing with unique IDs here but rather 2D and 3D geometries,
#   the relationships between rows don't really map well to the traditional
#   foreign key-style ActiveRecord associations.
module ActiveRecordSpatial::Associations
  extend ActiveSupport::Concern

  DEFAULT_OPTIONS = {
    :relationship => :intersects,
    :geom => ActiveRecordSpatial.default_column_name,
    :foreign_geom => ActiveRecordSpatial.default_column_name,
    :scope_options => {
      :invert => true
    }
  }.freeze

  module ClassMethods #:nodoc:
    def build_options(options)
      if !options[:foreign_geom] && options[:as]
        options[:foreign_geom] = "#{options[:as]}_geom"
      end

      if options[:geom].is_a?(Hash)
        options[:geom][:name] ||= ActiveRecordSpatial.default_column_name
      end

      DEFAULT_OPTIONS.deep_merge(options)
    end
    private :build_options
  end
end

