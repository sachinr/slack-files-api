# Create a JSON service account key here:
#
# https://console.cloud.google.com/apis/credentials/serviceaccountkey
#
# then run with
#
#   GOOGLE_APPLICATION_CREDENTIALS=<file>.json IMG=... ruby google.rb
#
# http://www.rubydoc.info/github/google/google-api-ruby-client/Google/Apis/VisionV1/VisionService

require 'googleauth'
require 'google/apis/vision_v1'
require 'rmagick'

PATH='./files/zuck.jpg'

Vision = Google::Apis::VisionV1
service = Vision::VisionService.new

scopes = ['https://www.googleapis.com/auth/cloud-platform']
authorization = Google::Auth.get_application_default(scopes)
service.authorization = authorization

content = File.read(PATH)
image = Vision::Image.new(content: content)
feature = Vision::Feature.new(type: 'FACE_DETECTION')
req = Vision::BatchAnnotateImagesRequest.new(requests: [
  {
    image: image,
    features: [feature]
  }
])
# https://cloud.google.com/prediction/docs/reference/v1.6/performance#partial
res = service.annotate_image(req, fields: 'responses(faceAnnotations(fd_bounding_poly))')

img = Magick::Image.read(PATH)[0]
gc = Magick::Draw.new

res.responses.first.face_annotations.each do |face|
  arr = face.fd_bounding_poly.to_h[:vertices].map{|v| v.values}
  points = arr.map{ |pair| pair.reverse }.flatten
  gc.stroke('red')
  gc.fill_opacity('0%')
  gc.polygon(*points)
  gc.draw(img)
end

img.write('divided.jpeg')
